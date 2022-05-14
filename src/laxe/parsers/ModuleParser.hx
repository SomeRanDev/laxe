package laxe.parsers;

#if (macro || laxeRuntime)

import sys.io.File;

import haxe.io.Path;

import haxe.macro.Context;
import haxe.macro.Expr;

import laxe.ast.Decor;
import laxe.ast.DecorManager;

import laxe.parsers.Parser;

@:nullSafety(Strict)
enum LaxeModuleMember {
	Variable(name: String, pos: Position, meta: Array<MetadataEntry>, type: FieldType, access: Array<Access>);
	Function(name: String, pos: Position, meta: Array<MetadataEntry>, type: FieldType, access: Array<Access>);
	Class(name: String, pos: Position, meta: Array<MetadataEntry>, params: Null<Array<TypeParamDecl>>, kind: TypeDefKind, fields: Array<Field>);
}

@:nullSafety(Strict)
class ModuleParser {
	var modulePath: String;
	var types: Array<TypeDefinition>;
	var imports: Null<Array<ImportExpr>>;
	var usings: Null<Array<TypePath>>;

	var p: Parser;
	var decorManager: DecorManager;

	var members: Array<{ member: LaxeModuleMember, metadata: Parser.Metadata }>;
	var decors: Array<Decor>;

	public function new(filePath: String, path: Path) {
		modulePath = generateModulePath(path);
		types = [];
		imports = null;
		usings = null;

		final content = File.getContent(filePath);

		decorManager = new DecorManager();

		p = new Parser(content, filePath, this);
		members = [];
		decors = [];

		parseModule();
	}

	public function addDecorPointer(d: DecorPointer) {
		decorManager.addPointer(d);
	}

	function parseModule() {
		var lastIndex = null;

		while(!p.ended) {
			p.parseWhitespaceOrComments();

			if(lastIndex != p.getIndex()) {
				lastIndex = p.getIndex();
			} else {
				p.errorHere("Unexpected content at module-level");
				break;
			}

			final metadata = p.parseAllNextDecors();

			if(parseDecor(metadata)) {
				continue;
			}

			{
				final member = parseFunctionOrVariable();
				if(member != null) {
					members.push({ member: member, metadata: metadata });
					continue;
				}
			}

			{
				final member = parseClass();
				if(member != null) {
					members.push({ member: member, metadata: metadata });
					continue;
				}
			}
		}
	}

	public function applyMeta() {
		decorManager.ApplyDecors();

		for(m in members) {
			addMemberToTypes(m.member, m.metadata);
		}
	}

	function addMemberToTypes(member: LaxeModuleMember, metadata: Parser.Metadata) {
		switch(member) {
			case Variable(name, pos, meta, type, access): {
				types.push({
					pos: pos,
					pack: [],
					name: name,
					meta: metadata.string != null ? meta.concat(metadata.string) : meta,
					kind: TDField(type, access),
					fields: []
				});
			}
			case Function(name, pos, meta, type, access): {
				types.push({
					pos: pos,
					pack: [],
					name: name,
					meta: metadata.string != null ? meta.concat(metadata.string) : meta,
					kind: TDField((type), access),
					fields: []
				});
			}
			case Class(name, pos, meta, params, kind, fields): {
				types.push({
					pos: pos,
					pack: [],
					name: name,
					meta: metadata.string != null ? meta.concat(metadata.string) : meta,
					params: params,
					kind: kind,
					fields: fields
				});
			}
		}
	}

	function getPositionFromMember(member: LaxeModuleMember): Position {
		return switch(member) {
			case Variable(_, pos, _, _, _) |
				Function(_, pos, _, _, _) |
				Class(_, pos, _, _, _): pos;
		}
	}

	function generateModulePath(p: Path) {
		return if(p.file.length > 0) {
			var result = p.dir == null ? p.file : Path.normalize(Path.join([p.dir, p.file]));
			result = StringTools.replace(result, "/", ".");
			result = StringTools.replace(result, "\\", ".");
			result;
		} else {
			"";
		}
	}

	public function defineModule() {
		Context.defineModule(modulePath, types, imports, usings);
	}

	// ========================================
	// * Parsing
	// ========================================

	function parseClassFields(startIndent: String, classTypeName: String = "class"): Array<Field> {
		final fields = [];

		if(p.findAndParseNextContent(";")) {
		} else if(p.findAndParseNextContent(":")) {
			final currentLine = p.lineNumber;
			p.parseWhitespaceOrComments();

			var classIndent = null;
			if(currentLine != p.lineNumber) {
				classIndent = p.getIndent();
				if(!StringTools.startsWith(classIndent, startIndent)) {
					p.errorHere("Inconsistent indentation");
					classIndent = null;
				}
			} else {
				p.errorHere('Unexpected content on same line after $classTypeName :');
			}

			if(classIndent != null) {
				while(classIndent == p.getIndent()) {
					final mem = parseFunctionOrVariable();
					if(mem != null) {
						final field = convertModuleMemberToField(mem);
						if(field != null) {
							fields.push(field);
						} else {
							p.error('Unexpected member in $classTypeName body', getPositionFromMember(mem));
							break;
						}
					} else {
						p.errorHere("Expected field or function");
						break;
					}
					p.parseWhitespaceOrComments();
				}
			}
		}

		return fields;
	}

	static function convertModuleMemberToField(m: LaxeModuleMember): Null<Field> {
		return switch(m) {
			case Variable(name, pos, meta, type, access): {
				{
					name: name,
					pos: pos,
					meta: meta,
					kind: type,
					access: access
				};
			}
			case Function(name, pos, meta, type, access): {
				{
					name: name,
					pos: pos,
					meta: meta,
					kind: type,
					access: access
				};
			}
			case _: null;
		}
	}

	function parseFunctionOrVariable(): Null<LaxeModuleMember> {
		final state = p.saveParserState();
		final startIndex = p.getIndex();
		final access = p.parseAllAccessWithPublic();

		final ident = p.parseNextIdent();
		if(ident != null) {
			final name = ident.ident;
			if(name == "def") {
				return parseFunctionAfterDef(startIndex, access);
			} else if(name == "var" || name == "let" || name == "mut") {
				return parseVariableAfterLet(ident, startIndex, access);
			}
		}
		p.restoreParserState(state);
		return null;
	}

	function parseFunctionAfterDef(startIndex: Int, access: Array<Access>): Null<LaxeModuleMember> {
		final name = p.parseNextIdent();

		if(name != null) {
			var args = p.parseNextFunctionArgs();
			if(args == null) args = [];

			final retType = if(p.findAndParseNextContent("->")) {
				p.parseNextType();
			} else {
				null;
			}

			final expr = if(p.findAndCheckAhead(":")) {
				p.parseBlock();
			} else if(p.findAndParseNextContent("=")) {
				p.parseWhitespaceOrComments();
				final result = p.parseNextExpression();
				p.findAndParseNextContent(";");
				result;
			} else {
				null;
			}

			final ffun = FFun({
				args: args,
				ret: retType,
				expr: expr
			});
			return Function(name.ident, p.makePosition(startIndex), [], ffun, access);
		} else {
			p.errorHere("Expected function name");
		}

		return null;
	}

	function parseVariableAfterLet(varIdent: Parser.StringAndPos, startIndex: Int, access: Array<Access>): Null<LaxeModuleMember> {
		final name = p.parseNextIdent();
		if(name != null) {
			final type = if(p.findAndParseNextContent(":")) {
				p.parseNextType();
			} else {
				null;
			}

			final e = if(p.findAndParseNextContent("=")) {
				p.parseNextExpression();
			} else {
				null;
			}

			p.findAndParseNextContent(";");

			final meta = if(varIdent.ident == "let") {
				[ { name: ":final", pos: varIdent.pos } ];
			} else {
				null;
			}

			return Variable(name.ident, p.makePosition(startIndex), meta, FVar(type, e), access);
		} else {
			p.errorHere("Expected variable name");
		}

		return null;
	}

	function parseClass(): Null<LaxeModuleMember> {
		final state = p.saveParserState();

		final startIndex = p.getIndex();
		final startIndent = p.getIndent();

		final isFinalAbstract = p.tryParseMultiIdentOneEach("final", "abstract");
		var isFinal = false;
		var isAbstract = false;
		for(i in isFinalAbstract) {
			if(i.ident == "final") isFinal = true;
			else if(i.ident == "abstract") isAbstract = true;
		}

		final classIdent = p.tryParseOneIdent("class", "struct", "interface");
		if(classIdent != null) {
			final name = p.parseNextIdent();
			if(name != null) {
				final params = p.parseTypeParamDecls();

				final superType = if(p.tryParseIdent("extends") != null) {
					p.parseNextTypePath();
				} else {
					null;
				}

				final interfaces = [];
				while(p.tryParseIdent("implements") != null) {
					final interfaceType = p.parseNextTypePath();
					if(interfaceType != null) {
						interfaces.push(interfaceType);
					} else {
						p.errorHere("Expected interface type");
					}
				}

				final fields = parseClassFields(startIndent);

				final meta = if(classIdent.ident == "struct") {
					[ { name: ":struct", pos: classIdent.pos } ];
				} else {
					[];
				}
				
				final tdClass = TDClass(superType, interfaces, name.ident == "interface", isFinal, isAbstract);
				return Class(name.ident, p.makePosition(startIndex), meta, params, tdClass, fields);
			} else {
				p.errorHere("Expected class name");
			}
		} else {
			p.restoreParserState(state);
		}

		return null;
	}

	function parseDecor(metadata: Parser.Metadata): Bool {
		final state = p.saveParserState();

		final startIndex = p.getIndex();
		final startIndent = p.getIndent();

		final decorIdent = p.tryParseIdent("decor");
		if(decorIdent != null) {
			final name = p.parseNextIdent();
			if(name != null) {
				final fields = parseClassFields(startIndent, "decor");
				final d = new Decor(p, name.ident, fields, metadata);
				decors.push(d);
				return true;
			} else {
				p.errorHere("Expected decor name");
			}
		} else {
			p.restoreParserState(state);
		}

		return false;
	}
}

#end
