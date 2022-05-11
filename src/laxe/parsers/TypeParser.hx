package laxe.parsers;

#if (macro || laxeRuntime)

import laxe.types.Tuple;

import haxe.macro.Expr;

class TypeParser {
	public static function parseType(p: Parser): ComplexType {
		p.parseWhitespaceOrComments();
		final startIndex = p.getIndex();

		if(p.checkAhead("(")) {
			p.incrementIndex(1);
			final typeList = parseTypeList(p, ")");

			final returnType = if(p.findAndCheckAhead("->")) {
				p.incrementIndex(2);
				parseType(p);
			} else {
				null;
			}

			return if(returnType != null) {
				TFunction(typeList, returnType);
			} else {
				Tuple.ensure(typeList.length);
				TPath({
					pack: ["laxe"],
					name: "Tuple",
					sub: "Tuple" + typeList.length,
					params: typeList.map(t -> TPType(t))
				});
			}
		}

		final idents = [];

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

		if(idents.length == 1) {
			if(startsWithLowerCase(idents[0].ident)) {
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
					return TPath({ pack: [], name: name });
				}
			}
		}

		final pack = [];
		var name = "";
		var sub = null;
		var mode = 0;

		for(i in idents) {
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

		var params = null;
		if(p.findAndCheckAhead("<")) {
			p.incrementIndex(1);
			final typeList = parseTypeList(p, ">");
			params = typeList.map(t -> TPType(t));
		}

		var result = TPath({
			pack: pack,
			name: name,
			sub: sub,
			params: params
		});

		while(true) {
			if(p.findAndCheckAhead("?")) {
				result = TPath({
					pack: [],
					name: "Null",
					params: [TPType(result)]
				});
			} else if(p.findAndCheckAhead("[]")) {
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

	static function parseTypeList(p: Parser, endChar: String): Array<ComplexType> {
		final result = [];

		if(!p.findAndCheckAhead(endChar)) {
			while(true) {
				p.parseWhitespaceOrComments();
				if(p.ended) {
					p.errorHere("Unexpected end of file");
					break;
				}

				result.push(parseType(p));

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
