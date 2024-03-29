package laxe.parsers;

#if (macro || laxeRuntime)

import laxe.types.Tuple;

import laxe.parsers.Parser.StringAndPos;

import haxe.macro.Expr;

class TypeParser {
	public static function parseType(p: Parser): ComplexType {
		p.parseWhitespaceOrComments();
		final startIndex = p.getIndex();

		if(p.findAndParseNextContent("(")) {
			final typeList = parseTypeList(p, ")", true);

			final returnType = if(p.findAndCheckAhead("->")) {
				p.incrementIndex(2);
				parseType(p);
			} else {
				null;
			}

			return if(returnType != null) {
				TFunction(typeList.map(t -> t.type), returnType);
			} else {
				final names = [];
				var anyHasName = false;
				for(t in typeList) {
					if(t.name != null) {
						anyHasName = true;
						names.push(t.name != null ? t.name : "");
					}
				}
				if(anyHasName) {
					final path: TypePath = Tuple.ensureNamed(names, typeList.map(t -> t.type));
					TPath(path);
				} else {
					Tuple.ensure(typeList.length);
					TPath({
						pack: ["laxe"],
						name: "Tuple",
						sub: "Tuple" + typeList.length,
						params: typeList.map(t -> TPType(t.type))
					});
				}
			}
		}

		if(p.findAndParseNextContent("{")) {
			final typeList = parseTypeList(p, "}", true);
			for(t in typeList) {
				if(t.name == null) {
					p.error("Type name expected", t.pos);
				} else {
					return TAnonymous(typeList.map(t -> ({
						pos: t.pos,
						name: t.name,
						kind: FVar(t.type),
						access: []
					} : Field)));
				}
			}
		}

		var idents = [];

		final ident = p.parseNextIdent();
		if(ident != null) {
			idents.push(ident);
		} else {
			p.errorHere("Expected type name");
		}

		while(true) {
			p.parseWhitespaceOrComments();
			if(p.ended) {
				p.errorHere("Unexpected end of file");
				break;
			}

			if(p.findAndCheckAhead(".")) {
				p.incrementIndex(1);
				final ident = p.parseNextIdent();
				if(ident != null) {
					idents.push(ident);
				} else {
					p.errorHere("Expected type name");
				}
			} else {
				break;
			}
		}

		final typePath: TypePath = if(idents.length == 1 && startsWithLowerCase(idents[0].ident)) {
			switch(idents[0].ident) {
				case "expr`": {
					{ pack: ["laxe", "stdlib"], name: "LaxeExpr" };
				}
				case "typeDef`": {
					{ pack: ["laxe", "stdlib"], name: "LaxeTypeDefinition" };
				}
				case "field`": {
					{ pack: ["laxe", "stdlib"], name: "LaxeField" };
				}
				case "str": {
					if(p.useHaxeTypesForPrims) {
						{ pack: [], name: "String" };
					} else {
						{ pack: ["laxe", "stdlib"], name: "LaxeString" };
					}
				}
				case _: {
					final name = switch(idents[0].ident) {
						case "int": "Int";
						case "float": "Float";
						case "bool": "Bool";
						case "str": "String";
						case "void": "Void";
						case "dyn": "Dynamic";
						case "any": "Any";
						case _: null;
					}
					if(name != null) {
						idents = [{ ident: name, pos: idents[0].pos }];
					}
					convertIdentListToTypePath(p, idents);
				}
			}
		} else {
			convertIdentListToTypePath(p, idents);
		}

		typePath.params = null;
		if(p.findAndParseNextContent("<")) {
			final typeList = parseTypeList(p, ">");
			typePath.params = typeList.map(t -> TPType(t.type));
		}

		var result = TPath(typePath);

		while(true) {
			if(p.parseNextContent("?")) {
				result = TPath({
					pack: [],
					name: "Null",
					params: [TPType(result)]
				});
			} else if(p.parseNextContent("[]")) {
				result = TPath({
					pack: [],
					name: "Array",
					params: [TPType(result)]
				});
			} else {
				break;
			}
		}

		return result;
	}

	public static function convertIdentListToTypePath(p: Parser, identList: Array<StringAndPos>): TypePath {
		final pack = [];
		var name = "";
		var sub = null;
		var mode = 0;

		for(i in identList) {
			if(mode == 0) {
				if(!startsWithLowerCase(i.ident)) {
					name = i.ident;
					mode = 1;
				} else {
					pack.push(i.ident);
				}
			} else if(mode == 1 && !startsWithLowerCase(i.ident)) {
				sub = i.ident;
				mode = 2;
			} else {
				final msg = if(mode == 2) {
					"Unexpected identifier. Nothing should exist beyond sub-type?";
				} else {
					"Unexpected identifier. All packages type should start lowercase.";
				}
				p.error(msg, i.pos);
			}
		}

		if(name.length <= 0 && pack.length > 0) {
			name = pack.pop();
		}

		return {
			pack: pack,
			name: name,
			sub: sub,
			params: null
		};
	}

	public static function parseTypeList(p: Parser, endChar: String, allowNames: Bool = false): Array<{ name: Null<String>, type: ComplexType, pos: Null<Position> }> {
		final result = [];

		if(!p.findAndCheckAhead(endChar)) {
			while(true) {
				p.parseWhitespaceOrComments();
				if(p.ended) {
					p.errorHere("Unexpected end of file");
					break;
				}

				final startIndex = p.getIndex();
				final t = parseType(p);
				if(p.findAndParseNextContent(":")) {
					if(!allowNames) {
						p.errorHere("Expected ',' or '" + endChar + "'");
					} else {
						final name = switch(t) {
							case TPath(path): path.pack.join("") + path.name;
							case _: null;
						}
						result.push({ name: name, type: parseType(p), pos: p.makePosition(startIndex) });
					}
				} else {
					result.push({ name: null, type: t, pos: p.makePosition(startIndex) });
				}
				
				if(p.findAndCheckAhead(endChar)) {
					p.incrementIndex(endChar.length);
					break;
				} else if(p.findAndCheckAhead(",")) {
					p.incrementIndex(1);
					continue;
				} else {
					p.errorHere("Expected ',' or '" + endChar + "'");
					break;
				}
			}
		} else {
			p.incrementIndex(endChar.length);
		}

		return result;
	}

	static function startsWithLowerCase(s: String): Bool {
		return s.length > 0 && s.charAt(0).toLowerCase() == s.charAt(0);
	}
}

#end
