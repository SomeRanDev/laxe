package laxe.parsers;

#if (macro || laxeRuntime)

import sys.io.File;

import haxe.io.Path;

import haxe.macro.Context;
import haxe.macro.Expr;

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

	public function new(filePath: String, path: Path) {
		modulePath = generateModulePath(path);
		types = [];
		imports = null;
		usings = null;

		final content = File.getContent(filePath);

		final parser = new Parser(content, filePath);

		var lastIndex = null;

		while(!parser.ended) {
			parser.parseWhitespaceOrComments();

			if(lastIndex != parser.getIndex()) {
				lastIndex = parser.getIndex();
			} else {
				parser.errorHere("Unexpected content at module-level");
				break;
			}

			{
				final member = parseFunctionOrVariable(parser);
				if(member != null) addMemberToTypes(member);
			}

			{
				final member = parseClass(parser);
				if(member != null) addMemberToTypes(member);
			}
		}

		trace("Done");
	}

	function addMemberToTypes(member: LaxeModuleMember) {
		switch(member) {
			case Variable(name, pos, meta, type, access): {
				types.push({
					pos: pos,
					pack: [],
					name: name,
					meta: meta,
					kind: TDField(type, access),
					fields: []
				});
			}
			case Function(name, pos, meta, type, access): {
				types.push({
					pos: pos,
					pack: [],
					name: name,
					meta: meta,
					kind: TDField((type), access),
					fields: []
				});
			}
			case Class(name, pos, meta, params, kind, fields): {
				types.push({
					pos: pos,
					pack: [],
					name: name,
					meta: meta,
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

	function parseFunctionOrVariable(p: Parser): Null<LaxeModuleMember> {
		final state = p.saveParserState();
		final startIndex = p.getIndex();
		final access = p.parseAllAccessWithPublic();

		final ident = p.parseNextIdent();
		if(ident != null) {
			final name = ident.ident;
			if(name == "def") {
				return parseFunctionAfterDef(p, startIndex, access);
			} else if(name == "var" || name == "let" || name == "mut") {
				return parseVariableAfterLet(p, ident, startIndex, access);
			}
		}
		p.restoreParserState(state);
		return null;
	}

	function parseFunctionAfterDef(p: Parser, startIndex: Int, access: Array<Access>): Null<LaxeModuleMember> {
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

	function parseVariableAfterLet(p: Parser, varIdent: Parser.StringAndPos, startIndex: Int, access: Array<Access>): Null<LaxeModuleMember> {
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

	function parseClass(p: Parser): Null<LaxeModuleMember> {
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
						p.errorHere("Unexpected content on same line after class :");
					}

					if(classIndent != null) {
						while(classIndent == p.getIndent()) {
							final mem = parseFunctionOrVariable(p);
							if(mem != null) {
								final field = convertModuleMemberToField(mem);
								if(field != null) {
									fields.push(field);
								} else {
									p.error("Unexpected member in class body", getPositionFromMember(mem));
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
				
				final tdClass = TDClass(superType, interfaces, name.ident == "interface", isFinal, isAbstract);
				return Class(name.ident, p.makePosition(startIndex), [], params, tdClass, fields);
			} else {
				p.errorHere("Expected class name");
			}
		} else {
			p.restoreParserState(state);
		}

		return null;
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
}

#end
