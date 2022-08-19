package laxe.parsers;

#if (macro || laxeRuntime)

import sys.io.File;

import haxe.io.Path;

import haxe.macro.Context;
import haxe.macro.Expr;

import laxe.ast.MacroManager;
import laxe.ast.DecorManager;
import laxe.ast.ResolveDefaultValue;
import laxe.ast.comptime.Decor;
import laxe.ast.comptime.MacroFunc;

import laxe.parsers.Parser;

@:nullSafety(Strict)
enum LaxeModuleMember {
	Variable(name: String, pos: Position, meta: Array<MetadataEntry>, type: FieldType, access: Array<Access>);
	Function(name: String, pos: Position, meta: Array<MetadataEntry>, type: FieldType, access: Array<Access>);
	Class(name: String, pos: Position, meta: Array<MetadataEntry>, params: Null<Array<TypeParamDecl>>, kind: TypeDefKind, fields: Array<Field>);
	TypeAlias(name: String, pos: Position, meta: Array<MetadataEntry>, params: Null<Array<TypeParamDecl>>, alias: ComplexType);
	Enum(name: String, pos: Position, meta: Array<MetadataEntry>, params: Null<Array<TypeParamDecl>>, enumFields: Array<Field>, abstractFields: Array<Field>);
}

@:nullSafety(Strict)
class ModuleParser {
	var moduleName: String;
	var modulePath: String;

	var types: Array<TypeDefinition>;
	var imports: Null<Array<ImportExpr>>;
	var usings: Null<Array<TypePath>>;

	var importedModules: Map<String, ModuleParser>;
	var importedDecors: Array<Decor>;
	var importedMacros: Array<MacroFunc>;

	var p: Parser;
	var decorManager: DecorManager;
	var macroManager: MacroManager;

	var members: Array<{ member: LaxeModuleMember, metadata: Parser.Metadata }>;
	var decors: Array<Decor>;
	var macros: Array<MacroFunc>;

	static var LaxeModuleMap: Map<String, ModuleParser> = [];

	public function new(filePath: String, path: Path) {
		modulePath = generateModulePath(path);
		moduleName = {
			final arr = modulePath.split(".");
			arr[arr.length - 1];
		};
		LaxeModuleMap[modulePath] = this;

		types = [];
		imports = null;
		usings = null;

		importedModules = [];
		importedDecors = [];
		importedMacros = [];

		var content = File.getContent(filePath);
		if(!StringTools.endsWith(content, "\n")) {
			content += "\n";
		}

		decorManager = new DecorManager();
		macroManager = new MacroManager();

		p = new Parser(content, filePath, this);
		members = [];
		decors = [];
		macros = [];

		parseModule();
	}

	public function addExprDecorPointer(d: DecorPointer) {
		decorManager.addPointer(d);
	}

	public function addExprMacroPointer(m: MacroPointer) {
		macroManager.addPointer(m);
	}

	function parseModule() {
		var lastIndex = null;

		p.parseWhitespaceOrComments();

		final importsAndUsings = p.parseAllNextImports();
		for(iu in importsAndUsings) {
			switch(iu) {
				case Left(imp): {
					if(imports == null) imports = [];
					imports.push(imp);
				}
				case Right(use): {
					if(usings == null) usings = [];
					usings.push(use);
				}
			}
		}

		while(!p.ended) {
			p.parseWhitespaceOrComments();

			if(lastIndex != p.getIndex()) {
				lastIndex = p.getIndex();
			} else {
				p.errorHere("Unexpected content at module-level");
				break;
			}

			final metadata = p.parseAllNextDecors();

			if(parseDecor(metadata) || parseMacro(metadata)) {
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

			{
				final member = parseEnum(metadata);
				if(member != null) {
					members.push({ member: member, metadata: metadata });
					continue;
				}
			}

			{
				final member = parseWrapper();
				if(member != null) {
					members.push({ member: member, metadata: metadata });
					continue;
				}
			}

			{
				final member = parseTypeAlias();
				if(member != null) {
					members.push({ member: member, metadata: metadata });
					continue;
				}
			}
		}
	}

	// ========================================
	// * Processing
	// ========================================

	public function processModule() {
		processImports();
		processUsings();
		processMembers();
		processDecors();
		processMacros();
	}

	function processImports() {
		if(imports != null) {
			final importsToBeDeleted = [];
			for(i in 0...imports.length) {
				final p = imports[i].path;
				final names = p.map(p -> p.name);
				final name = names.join(".");
				if(LaxeModuleMap.exists(name)) {
					final m = LaxeModuleMap[name];
					importedModules[m.moduleName] = m;
				} else {
					final subName = names.pop();
					final modName = names.join(".");
					if(LaxeModuleMap.exists(modName)) {
						var found = false;
						final m = LaxeModuleMap[modName];
						for(decor in m.decors) {
							if(decor.name == subName) {
								importedDecors.push(decor);
								importsToBeDeleted.push(i);
								found = true;
								break;
							}
						}
						if(!found) {
							for(mac in m.macros) {
								if(mac.name == subName) {
									importedMacros.push(mac);
									importsToBeDeleted.push(i);
									break;
								}
							}
						}
					}
				}
			}

			while(importsToBeDeleted.length > 0) {
				final index = importsToBeDeleted.pop();
				imports.splice(index, 1);
			}
		}
	}

	function processUsings() {
		if(usings != null) {
			final usingsToBeDeleted = [];
			for(i in 0...usings.length) {
				final u = usings[i];
				final mPath = (u.pack.length > 0 ? u.pack.join(".") : "") + "." + u.name;
				if(LaxeModuleMap.exists(mPath)) {
					final m = LaxeModuleMap[mPath];
					if(u.sub == null) {
						importedModules[m.moduleName] = m;
					} else {
						var found = false;
						for(decor in m.decors) {
							if(decor.name == u.sub) {
								importedDecors.push(decor);
								usingsToBeDeleted.push(i);
								found = true;
								break;
							}
						}
						if(!found) {
							for(mac in m.macros) {
								if(mac.name == u.sub) {
									importedMacros.push(mac);
									usingsToBeDeleted.push(i);
									break;
								}
							}
						}
					}
				}
			}

			while(usingsToBeDeleted.length > 0) {
				final index = usingsToBeDeleted.pop();
				usings.splice(index, 1);
			}
		}
	}

	function processDecors() {
		decorManager.ApplyDecors(this);
	}

	function processMacros() {
		macroManager.ApplyMacros(this);
	}

	function processMembers() {
		for(m in members) {
			addMemberToTypes(m.member, m.metadata);
		}
	}

	public function findDecorFromTypePath(typePath: TypePath) {
		final name = typePath.name;
		if(typePath.pack.length == 0 && typePath.sub == null) {
			for(d in decors) {
				if(d.name == name) {
					return d;
				}
			}
			for(d in importedDecors) {
				if(d.name == name) {
					return d;
				}
			}
		}

		if(typePath.pack.length == 0 && typePath.sub != null) {
			final m = importedModules[typePath.name];
			for(d in m.decors) {
				if(d.name == typePath.sub) {
					return d;
				}
			}
		}

		final targetDotPath = typePath.pack.join(".") + "." + typePath.name;
		for(m in laxe.Laxe.Modules) {
			if(m.modulePath == targetDotPath) {
				for(d in m.decors) {
					if(d.name == typePath.sub || d.name == name) {
						return d;
					}
				}
			}
		}

		return null;
	}

	public function findMacroFromTypePath(typePath: TypePath) {
		final name = typePath.name;
		if(typePath.pack.length == 0 && typePath.sub == null) {
			for(m in macros) {
				if(m.name == name) {
					return m;
				}
			}
			for(m in importedMacros) {
				if(m.name == name) {
					return m;
				}
			}
		}

		if(typePath.pack.length == 0 && typePath.sub != null) {
			final module = importedModules[typePath.name];
			for(m in module.macros) {
				if(m.name == typePath.sub) {
					return m;
				}
			}
		}

		final targetDotPath = typePath.pack.join(".") + "." + typePath.name;
		for(module in laxe.Laxe.Modules) {
			if(module.modulePath == targetDotPath) {
				for(m in module.macros) {
					if(m.name == typePath.sub || m.name == name) {
						return m;
					}
				}
			}
		}

		return null;
	}

	function addMemberToTypes(member: LaxeModuleMember, metadata: Parser.Metadata) {
		var typeDef: Null<TypeDefinition> = null;
		switch(member) {
			case Variable(name, pos, meta, type, access): {
				typeDef = {
					pos: pos,
					pack: [],
					name: name,
					meta: metadata.string != null ? meta.concat(metadata.string) : meta,
					kind: TDField(type, access),
					fields: []
				};
			}
			case Function(name, pos, meta, type, access): {
				typeDef = {
					pos: pos,
					pack: [],
					name: name,
					meta: metadata.string != null ? meta.concat(metadata.string) : meta,
					kind: TDField((type), access),
					fields: []
				};
			}
			case Class(name, pos, meta, params, kind, fields): {
				typeDef = {
					pos: pos,
					pack: [],
					name: name,
					meta: metadata.string != null ? meta.concat(metadata.string) : meta,
					params: params,
					kind: kind,
					fields: fields
				};
			}
			case TypeAlias(name, pos, meta, params, type): {
				typeDef = {
					pos: pos,
					pack: [],
					name: name,
					meta: metadata.string != null ? meta.concat(metadata.string) : meta,
					params: params,
					kind: TDAlias(type),
					fields: []
				};
			}
			case Enum(name, pos, meta, params, enumFields, abstractFields): {
				if(abstractFields.length == 0) {
					typeDef = {
						pos: pos,
						pack: [],
						name: name,
						meta: metadata.string != null ? meta.concat(metadata.string) : meta,
						params: params,
						kind: TDEnum,
						fields: enumFields
					};
				} else {
					final iType = "I" + name;
					final cType = TPath({
						pack: [],
						name: iType
					});

					types.push({
						pos: pos,
						pack: [],
						name: iType,
						meta: [],
						params: params,
						kind: TDEnum,
						fields: enumFields
					});
						
					typeDef = {
						pos: pos,
						pack: [],
						name: name,
						meta: metadata.string != null ? meta.concat(metadata.string) : meta,
						params: params,
						kind: TDAbstract(cType, [cType], [cType]),
						fields: abstractFields
					};
				}
			}
		}
		if(typeDef != null) {
			if(metadata.typed != null) {
				for(d in metadata.typed) {
					d.setTypeDef(typeDef);
					decorManager.addPointer(d);
				}
			}
			types.push(typeDef);
		}
	}

	function getPositionFromMember(member: LaxeModuleMember): Position {
		return switch(member) {
			case Variable(_, pos, _, _, _) |
				Function(_, pos, _, _, _) |
				Class(_, pos, _, _, _) |
				TypeAlias(_, pos, _, _, _) |
				Enum(_, pos, _, _, _, _): pos;
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
		if(types.length > 0) {
			Context.defineModule(modulePath, types, imports, usings);
		}
	}

	// ========================================
	// * Parsing
	// ========================================

	function parseClassFields(startIndent: String, classTypeName: String = "class"): Array<Field> {
		final fields = [];

		final isClass = classTypeName == "class";

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
					final metadata = p.parseAllNextDecors();
					final mem = parseFunctionOrVariable();
					if(mem != null) {
						final field = convertModuleMemberToField(mem, metadata);
						if(field != null) {
							fields.push(field);
						} else {
							p.error('Unexpected member in $classTypeName body', getPositionFromMember(mem));
							break;
						}
					} else if(classTypeName == "enum") {
						final caseStartIndex = p.getIndex();
						final name = p.parseNextIdent();
						if(name != null) {
							if(p.findAndParseNextContent("(")) {
								final typeList = TypeParser.parseTypeList(p, ")", true);
								var index = 0;
								final funcArgs = typeList.map(function(t) {
									final result: FunctionArg = {
										name: t.name != null ? t.name : ("_" + index),
										type: t.type
									};
									index++;
									return result;
								});
								fields.push({
									name: name.ident,
									pos: p.makePosition(caseStartIndex),
									kind: FFun({
										ret: null,
										params: [],
										expr: null,
										args: funcArgs
									}),
									meta: [{ name: "#isEnumCase", pos: p.noPosition() }],
									access: []
								});
							} else {
								final pos = p.makePosition(caseStartIndex);
								fields.push({
									name: name.ident,
									pos: pos,
									kind: FVar(null, null),
									meta: [{ name: "#isEnumCase", pos: p.noPosition() }],
									access: []
								});
							}
							p.findAndParseNextContent(";");
						} else {
							p.errorHere("Expected field, function, or identifier for enum case");
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

	function convertModuleMemberToField(m: LaxeModuleMember, metadata: Parser.Metadata): Null<Field> {
		final field = switch(m) {
			case Variable(name, pos, meta, type, access): {
				// If no default value assigned, set one if the type has one.
				// Otherwise, Haxe will default all types to null.
				switch(type) {
					case FVar(t, e): {
						if(t != null && e == null) {
							final newExpr = ResolveDefaultValue(t);
							if(newExpr != null) {
								type = FVar(t, newExpr);
							}
						}
					}
					case _:
				}

				{
					name: name,
					pos: pos,
					meta: metadata.string != null ? meta.concat(metadata.string) : meta,
					kind: type,
					access: access
				};
			}
			case Function(name, pos, meta, type, access): {
				{
					name: name,
					pos: pos,
					meta: metadata.string != null ? meta.concat(metadata.string) : meta,
					kind: type,
					access: access
				};
			}
			case _: null;
		}

		if(field != null) {
			if(metadata.typed != null) {
				for(d in metadata.typed) {
					d.setField(field);
					decorManager.addPointer(d);
				}
			}
		}

		return field;
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
			} else if(name == "var" || name == "const") {
				return parseVariableAfterVar(ident, startIndex, access);
			}
		}
		p.restoreParserState(state);
		return null;
	}

	function parseFunctionAfterDef(startIndex: Int, access: Array<Access>): Null<LaxeModuleMember> {
		final fun = p.parseFunctionAfterDef(true);
		final ffun = FFun(fun.f);
		return Function(fun.n, p.makePosition(startIndex), [], ffun, access);
	}

	function parseVariableAfterVar(varIdent: Parser.StringAndPos, startIndex: Int, access: Array<Access>): Null<LaxeModuleMember> {
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

			final meta = if(varIdent.ident == "const") {
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

				final tdClass = TDClass(superType, interfaces, classIdent.ident == "interface", isFinal, isAbstract);
				return Class(name.ident, p.makePosition(startIndex), meta, params, tdClass, fields);
			} else {
				p.errorHere("Expected class name");
			}
		} else {
			p.restoreParserState(state);
		}

		return null;
	}

	function parseEnum(metadata: Parser.Metadata): Null<LaxeModuleMember> {
		final state = p.saveParserState();
		final startIndex = p.getIndex();
		final startIndent = p.getIndent();

		final enumIdent = p.tryParseIdent("enum");
		if(enumIdent != null) {
			final name = p.parseNextIdent();
			if(name != null) {
				final params = p.parseTypeParamDecls();
				final fields = parseClassFields(startIndent, "enum");

				final enumFields = [];
				final abstractFields = [];

				for(f in fields) {
					var isEnumCase = -1;
					if(f.meta != null) {
						for(i in 0...f.meta.length) {
							if(f.meta[i].name == "#isEnumCase") {
								isEnumCase = i;
								break;
							}
						}
					}

					if(isEnumCase == -1) {
						abstractFields.push(f);
					} else {
						enumFields.push(f);
						f.meta = f.meta.splice(isEnumCase, 1);
					}
				}

				final selfPath = TPath({
					pack: [],
					name: name.ident
				});

				// This generates static fields to generate the enum values from the abstact name.
				// Unfortunately, it causes clashes with the interior enum values.
				// This behavior can be reenabled using @EnumBuilderFunctions
				var addBuilders = false;
				if(metadata.typed != null) {
					for(m in metadata.typed) {
						if(m.name() == "EnumBuilderFunctions") {
							addBuilders = true;
							metadata.typed.remove(m);
							break;
						}
					}
				}
				if(addBuilders && abstractFields.length > 0) {
					for(f in enumFields) {
						final fname = f.name;

						switch(f.kind) {
							case FVar(null, null): {
								abstractFields.push({
									name: fname,
									pos: f.pos,
									kind: FProp("get", "never", selfPath, null),
									meta: [],
									access: [APublic, AStatic]
								});

								abstractFields.push({
									name: "get_" + fname,
									pos: f.pos,
									kind: FFun({
										args: [],
										expr: macro return $i{"I"+name.ident}.$fname,
										ret: selfPath
									}),
									meta: [],
									access: [APublic, AStatic]
								});
							}
							case FFun(fun): {
								final ident = macro $i{"I"+name.ident}.$fname;
								final call = {
									expr: ECall(ident, fun.args.map(f -> macro $i{f.name})),
									pos: ident.pos
								};
								abstractFields.push({
									name: fname,
									pos: f.pos,
									kind: FFun({
										args: fun.args,
										expr: macro return $call,
										ret: selfPath
									}),
									meta: [],
									access: [APublic, AStatic]
								});
							}
							case _:
						}
					}
				}

				return Enum(name.ident, p.makePosition(startIndex), [], params, enumFields, abstractFields);
			} else {
				p.errorHere("Expected enum name");
			}
		} else {
			p.restoreParserState(state);
		}

		return null;
	}

	function parseWrapper(): Null<LaxeModuleMember> {
		final state = p.saveParserState();
		final startIndex = p.getIndex();
		final startIndent = p.getIndent();

		final wrapperIdent = p.tryParseIdent("wrapper");
		if(wrapperIdent != null) {
			final name = p.parseNextIdent();
			if(name != null) {
				final params = p.parseTypeParamDecls();

				final superType = if(p.tryParseIdent("extends") != null) {
					p.parseNextType();
				} else {
					p.errorHere("Expected 'extends' keyword");
					return null;
				}

				final from = [];
				final to = [];
				while(true) {
					if(p.tryParseIdent("from") != null) {
						final fromType = p.parseNextType();
						if(fromType != null) {
							from.push(fromType);
						} else {
							p.errorHere("Expected from type");
						}
					} else if(p.tryParseIdent("to") != null) {
						final toType = p.parseNextType();
						if(toType != null) {
							to.push(toType);
						} else {
							p.errorHere("Expected to type");
						}
					} else {
						break;
					}
				}

				final fields = parseClassFields(startIndent);

				final meta = [];

				final tdAbstract = TDAbstract(superType, from, to);
				return Class(name.ident, p.makePosition(startIndex), meta, params, tdAbstract, fields);
			} else {
				p.errorHere("Expected class name");
			}
		} else {
			p.restoreParserState(state);
		}

		return null;
	}

	function parseTypeAlias(): Null<LaxeModuleMember> {
		final state = p.saveParserState();
		final startIndex = p.getIndex();
		final startIndent = p.getIndent();

		final aliasIdent = p.tryParseIdent("alias");
		if(aliasIdent != null) {
			final typeIdent = p.tryParseIdent("type");
			if(typeIdent != null) {
				final name = p.parseNextIdent();
				if(name != null) {
					final params = p.parseTypeParamDecls();

					if(p.findAndParseNextContent("=")) {
						final type = p.parseNextType();
						p.findAndParseNextContent(";");
						if(type != null) {
							final meta = [];
							return TypeAlias(name.ident, p.makePosition(startIndex), meta, params, type);
						} else {
							p.errorHere("Expected type");
						}
					} else {
						p.errorHere("Expected '='");
					}
				} else {
					p.errorHere("Expected alias name");
				}
			} else {
				p.errorHere("Expected 'type' or 'decor' keyword here");
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
			final args = p.parseNextFunctionArgs();
			if(name != null) {
				final fields = parseClassFields(startIndent, "decor");
				final d = new Decor(p, name.ident, fields, args, metadata);
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

	function parseMacro(metadata: Parser.Metadata): Bool {
		final state = p.saveParserState();

		final startIndex = p.getIndex();

		final macroIdent = p.tryParseIdent("macro");
		if(macroIdent != null) {
			final funcData = p.parseFunctionAfterDef(true);
			final m = new MacroFunc(
				p,
				funcData.n,
				funcData.f.expr,
				funcData.f.ret,
				p.lastArgumentsParsed,
				metadata,
				p.makePosition(startIndex)
			);
			macros.push(m);
			return true;
		} else {
			p.restoreParserState(state);
		}

		return false;
	}
}

#end
