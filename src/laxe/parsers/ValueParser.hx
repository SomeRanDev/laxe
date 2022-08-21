package laxe.parsers;

#if (macro || laxeRuntime)

import haxe.macro.Expr;

import laxe.parsers.Parser;

class ValueParser {
	var parser: Parser;

	public static final rawStringOperator = "r";
	public static final stringOperator = "\"";
	public static final singleStringOperator = "'";
	public static final multilineStringOperatorStart = "\"\"\"";
	public static final multilineStringOperatorEnd = "\"\"\"";
	public static final multilineSingleStringOperatorStart = "'''";
	public static final multilineSingleStringOperatorEnd = "'''";

	public static final listSeparatorOperator = ",";
	public static final arrayOperatorStart = "[";
	public static final arrayOperatorEnd = "]";
	public static final tupleOperatorStart = "(";
	public static final tupleOperatorEnd = ")";

	public function new(parser: Parser) {
		this.parser = parser;
	}

	public function parseValueExpr(): Null<Expr> {
		var result = null;
		var count = 0;
		while(result == null && count <= 9) {
			switch(count) {
				case 0: result = parseNextNull();
				case 1: result = parseNextSelf();
				case 2: result = parseNextBoolean();
				case 3: result = parseArrayLiteral();
				case 4: result = parseAnonObjectLiteral();
				//case 4: result = parseTupleOrEnclosedLiteral();
				case 5: result = parseNextMultilineString();
				case 6: result = parseNextString();
				case 7: result = parseNextNumber();
				//case 8: result = parseTypeName();
				case 9: result = parseNextIdentifier();
			}
			count++;
		}
		return result;
	}

	public function parseNextNull(): Null<Expr> {
		final word = parser.tryParseOneIdent("null", "None");
		if(word != null) {
			return {
				expr: EConst(CIdent("null")),
				pos: word.pos
			};
		}
		return null;
	}

	public function parseNextSelf(): Null<Expr> {
		if(!parser.allowSelf) {
			return null;
		}
		final word = parser.tryParseOneIdent("self");
		if(word != null) {
			return {
				expr: EConst(CIdent("this")),
				pos: word.pos
			};
		}
		return null;
	}

	public function parseNextBoolean(): Null<Expr> {
		final word = parser.tryParseOneIdent("true", "false", "True", "False");
		if(word != null) {
			final ident = (word.ident == "true" || word.ident == "True") ? "true" : "false";
			return {
				expr: EConst(CIdent(ident)),
				pos: word.pos
			};
		}
		return null;
	}

	public function parseNextNumber(): Null<Expr> {
		var result = null;
		var count = 0;
		while(result == null && count <= 2) {
			switch(count) {
				case 0: result = parseNextHexNumber();
				case 1: result = parseNextBinaryNumber();
				case 2: result = parseDecimalNumber();
			}
			count++;
		}

		/*
		var literal: Null<Literal> = null;
		if(result != null && numberTypeParsed != null) {
			final format = count == 1 ? Hex : (count == 2 ? Binary : Decimal);
			literal = Number(result, format, numberTypeParsed);
		}*/

		return result;
	}

	@:nullSafety(Off)
	public function parseDecimalNumber(): Null<Expr> {
		final startIndex = parser.getIndex();

		var numberFlags = 0;
		var invalidChars = false;
		var charStart: Null<Int> = null;
		var hasDot = false;
		var isFloat = false;

		var result = null;
		if(parser.isNumberChar(parser.currentCharCode())) {
			result = "";
			while(parser.getIndex() < parser.getContent().length) {
				final char = parser.currentChar();
				if(parser.isDecimalNumberChar(parser.currentCharCode())) {
					result += char;
				} else if(parser.currentCharCode() == 46 /* period */) {
					final isDecimal = parser.isDecimalNumberChar(parser.charCodeAt(parser.getIndex() + 1));
					if(!hasDot && isDecimal) {
						result += ".";
						hasDot = true;
					} else {
						break;
					}
				} else if(validNumberSuffixCharacters().contains(char)) {
					if(charStart == null) {
						charStart = parser.getIndex();
					}
					var amount = 0;
					switch(char) {
						case "f": {
							if(isFloat) invalidChars = true;
							isFloat = true;
						}
					}
				} else {
					break;
				}
				if(parser.incrementIndex(1)) {
					break;
				}
			}
		}

		if(result != null) {
			if(!invalidChars) {
				return if(isFloat || hasDot) {
					final str = if(isFloat) {
						final noF = StringTools.replace(result, "f", "");
						if(!hasDot) {
							noF + ".0";
						} else {
							noF;
						};
					} else {
						result;
					};
					{
						expr: EConst(CFloat(str)),
						pos: parser.makePosition(startIndex)
					};
				} else {
					{
						expr: EConst(CInt(result)),
						pos: parser.makePosition(startIndex)
					};
				};
			}
			if(invalidChars) {
				parser.warn("Invalid number characters", parser.makePosition(charStart));
			}
		}

		return null;
	}

	public function parseHexOrBinaryNumber(isHex: Bool): Null<Expr> {
		final startIndex = parser.getIndex();
		final numberStarter = isHex ? "0x" : "0b";
		var result = null;
		if(parser.parseNextContent(numberStarter)) {
			result = numberStarter;
			while(parser.getIndex() < parser.getContent().length) {
				final charCode = parser.currentCharCode();
				if(parser.isDecimalNumberChar(charCode)) {
					result += parser.currentChar();
				} else {
					break;
				}
				if(parser.incrementIndex(1)) {
					break;
				}
			}
		}
		if(result == null) {
			return null;
		}
		return {
			expr: EConst(CInt(result)),
			pos: parser.makePosition(startIndex)
		};
	}

	public function validNumberSuffixCharacters(): Array<String> {
		return ["f"];
	}

	public function parseNextHexNumber(): Null<Expr> {
		return parseHexOrBinaryNumber(true);
	}

	public function parseNextBinaryNumber(): Null<Expr> {
		return parseHexOrBinaryNumber(false);
	}

	/*
	public function parseTypeName(): Null<Literal> {
		final namedType = parser.parseType(false);
		if(namedType != null) {
			return TypeName(namedType);
		}
		return null;
	}
	*/

	public function parseNextIdentifier(): Null<Expr> {
		final result = parser.parseNextIdent();

		if(result != null) {
			final e = switch(result.ident) {
				case "expr`": macro laxe.ast.LaxeExpr;
				case "typeDef`": macro laxe.ast.LaxeTypeDefinition;
				case "field`": macro laxe.ast.LaxeField;
				case "this": macro this_;
				case _: null;
			}
			if(e != null) {
				return {
					expr: e.expr,
					pos: result.pos
				};
			}
		}

		return result == null || result.ident == null ? null : {
			expr: EConst(CIdent(result.ident)),
			pos: result.pos
		};
	}

	public function parseNextMultilineString(): Null<Expr> {
		final startIndex = parser.getIndex();

		var start = multilineStringOperatorStart;
		var startSingle = multilineSingleStringOperatorStart;
		var isRaw = false;

		if(parser.checkAhead(rawStringOperator)) {
			start = rawStringOperator + start;
			startSingle = rawStringOperator + startSingle;
			isRaw = true;
		}

		var isSingle = false;
		var end = if(parser.parseNextContent(start)) {
			multilineStringOperatorEnd;
		} else if(parser.parseNextContent(startSingle)) {
			isSingle = true;
			multilineSingleStringOperatorEnd;
		} else {
			null;
		}

		var result: Null<String> = null;
		var wasSlash = false;
		if(end != null) {
			var endChar = end.charAt(0);

			result = "";
			while(true) {
				final char = parser.currentChar();
				if(char == endChar) {
					if(parser.parseNextContent(end)) {
						break;
					}
				} else if(!wasSlash && char == "\\") {
					if(isRaw) {
						@:nullSafety(Off) result += "\\";
					} else {
						wasSlash = true;
					}
				} else if(wasSlash) {
					if(char != null && !validEscapeCharacters().contains(char)) {
						// TODO: Unknown Escape Character
						//Error.addError(UnknownEscapeCharacter, parser, parser.getIndex() - 1, 1);
					}
					wasSlash = false;
				}
				@:nullSafety(Off) result += char;
				/*
				if(char == "\n") {
					parser.incrementLine();
				}
				*/
				if(parser.incrementIndex(1)) {
					break;
				}
			}
		}
		return result == null ? null : {
			expr: EConst(CString(result, isSingle ? SingleQuotes : DoubleQuotes)),
			pos: parser.makePosition(startIndex)
		};
	}

	public function parseNextString(): Null<Expr> {
		final startIndex = parser.getIndex();

		var start = stringOperator;
		var startSingle = singleStringOperator;
		var isRaw = false;

		if(parser.checkAhead(rawStringOperator)) {
			start = rawStringOperator + start;
			startSingle = rawStringOperator + startSingle;
			isRaw = true;
		}

		var isSingle = false;
		var end = if(parser.parseNextContent(start)) {
			stringOperator;
		} else if(parser.parseNextContent(startSingle)) {
			isSingle = true;
			singleStringOperator;
		} else {
			null;
		}

		var result: Null<String> = null;
		var wasSlash = false;
		if(end != null) {
			final endChar = end.charAt(0);

			result = "";
			while(true) {
				final char = parser.currentChar();
				if(!wasSlash && char == endChar) {
					if(parser.parseNextContent(end)) {
						break;
					}
				} else if(!wasSlash && char == "\\") {
					if(isRaw) {
						@:nullSafety(Off) result += "\\\\";
					} else {
						wasSlash = true;
					}
				} else if(wasSlash) {
					if(char != null && !validEscapeCharacters().contains(char)) {
						// TODO
						//Error.addError(UnknownEscapeCharacter, parser, parser.getIndex() - 1, 1);
					}
					wasSlash = false;
					@:nullSafety(Off) result += char;
				} else {
					@:nullSafety(Off) result += char;
				}
				if(parser.incrementIndex(1)) {
					break;
				}
			}
		}
		return result == null ? null : {
			expr: EConst(CString(result, isSingle ? SingleQuotes : DoubleQuotes)),
			pos: parser.makePosition(startIndex)
		};
	}

	public function validEscapeCharacters(): Array<String> {
		return ["n", "r", "t", "v", "f", "\\", "\"", "\'"];
	}

	function parseArrayLiteral(): Null<Expr> {
		final startIndex = parser.getIndex();
		if(parser.parseNextContent("[")) {
			final exprs = parser.parseNextExpressionList("]");
			return {
				expr: EArrayDecl(exprs),
				pos: parser.makePosition(startIndex)
			};
		}
		return null;
	}

	function parseAnonObjectLiteral(): Null<Expr> {
		final startIndex = parser.getIndex();
		if(parser.parseNextContent("{")) {
			final fields: Array<ObjectField> = [];
			while(!parser.parseNextContent("}")) {
				final ident = parser.parseNextIdent();
				if(ident == null) {
					parser.errorHere("Expected Identifier");
					break;
				} else {
					final expr = if(parser.parseNextContent(":")) {
						parser.parseNextExpression();
					} else {
						{
							expr: EConst(CIdent(ident.ident)),
							pos: ident.pos
						}
					}

					fields.push({
						field: ident.ident,
						expr: expr
					});

					if(parser.parseNextContent(",")) {
						continue;
					} else if(parser.parseNextContent("}")) {
						break;
					} else {
						parser.errorHere("Expected ',' or '}'");
						break;
					}
				}
			}

			return {
				expr: EObjectDecl(fields),
				pos: parser.makePosition(startIndex)
			};
		}
		return null;
	}

	/*
	public function parseTupleOrEnclosedLiteral(): Null<Literal> {
		final exprs = parseListType(tupleOperatorStart, tupleOperatorEnd);
		if(exprs != null && exprs.length == 1) {
			return EnclosedExpression(exprs[0]);
		}
		return exprs == null ? null : Tuple(exprs);
	}

	public function parseListType(start: String, end: String): Null<Array<TypedExpression>> {
		var result: Null<Array<TypedExpression>> = null;
		if(parser.parseNextContent(start)) {
			result = [];
			while(true) {
				if(parser.parseNextContent(end)) {
					break;
				}
				parser.parseWhitespaceOrComments();
				final expr = parser.parseExpression(false);
				if(expr != null) {
					final typedExpr = expr.getType(parser, parser.isPreliminary() ? Preliminary : Normal);
					if(typedExpr != null) {
						result.push(typedExpr);
						parser.parseNextContent(listSeparatorOperator);
					}
				} else {
					break;
				}
			}
		}
		return result;
	}*/
}

#end
