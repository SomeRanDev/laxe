package laxe.parsers;

#if (macro || laxeRuntime)

import haxe.macro.Expr;

import laxe.parsers.Parser;

import laxe.ast.Operators.Operator;
import laxe.ast.Operators.CallOperator;
import laxe.ast.Operators.PrefixOperators;
import laxe.ast.Operators.InfixOperators;
import laxe.ast.Operators.SuffixOperators;
import laxe.ast.Operators.CallOperators;

enum ExpressionParserMode {
	Prefix;
	Value;
	Suffix;
	Infix;
}

enum ExpressionParserPiece {
	Value(value: Expr);

	Prefix(op: Operator, pos: Position);
	Suffix(op: Operator, pos: Position);
	Call(op: CallOperator, params: Array<Expr>, pos: Position);
	Infix(op: Operator, pos: Position);

	Expression(e: Expr);
}

@:nullSafety(Strict)
class ExpressionParser {
	var parser: Parser;
	var sameLine: Bool;
	var mode: ExpressionParserMode;
	var pieces: Array<ExpressionParserPiece>;
	var expectedEndStrings: Null<Array<String>>;

	var startingIndex: Int;
	var foundExpectedString: Bool;
	var foundString: Null<String>;

	public function printAll() {
		for(p in pieces) {
			switch(p) {
				case Prefix(op, pos): trace(op.op);
				case Value(e): trace(haxe.macro.ExprTools.toString(e));
				case Suffix(op, pos): trace(op.op);
				case Call(op, params, pos): trace(op.op + op.opEnd);
				case Infix(op, pos): trace(op.op);
				case Expression(expr): trace(expr);
			}
		}
	}

	public function new(parser: Parser, sameLine: Bool = true, expectedEndStrings: Null<Array<String>> = null) {
		this.parser = parser;
		this.sameLine = sameLine;
		this.expectedEndStrings = expectedEndStrings;
		this.mode = Prefix;
		pieces = [];

		startingIndex = parser.getIndex();
		foundExpectedString = expectedEndStrings == null;

		parse();
	}

	public function successful() {
		return pieces.length > 0 && foundExpectedString;
	}

	function parse() {
		var cancelThreshold = 0;
		while(parser.getIndex() < parser.getContent().length) {
			parser.parseWhitespaceOrComments(sameLine);
			var oldIndex = parser.getIndex();
			switch(mode) {
				case Prefix: {
					if(!parsePrefix()) {
						mode = Value;
					}
				}
				case Value: {
					final result = parseValue();
					if(result) {
						mode = Suffix;
					} else {
						break;
					}
				}
				case Suffix: {
					if(!parseSuffixOrCall()) {
						mode = Infix;
					}
				}
				case Infix: {
					final result = parseInfix();
					if(result) {
						mode = Prefix;
					} else {
						break;
					}
				}
			}

			if(oldIndex == parser.getIndex()) {
				cancelThreshold++;
				if(++cancelThreshold > 10) {
					break;
				}
			} else {
				cancelThreshold = 0;
			}
		}

		if(expectedEndStrings != null) {
			parser.parseWhitespaceOrComments(sameLine);
			for(str in expectedEndStrings) {
				if(parser.checkAhead(str)) {
					foundString = str;
					foundExpectedString = true;
				}
			}
			if(!foundExpectedString) {
				// TODO: Unexpected Character After Expression
				//Error.addError(UnexpectedCharacterAfterExpression, parser, parser.getIndex());
			}
		}
	}

	function parsePrefix(): Bool {
		final startIndex = parser.getIndex();
		final op = checkForOperators(PrefixOperators);
		if(op != null) {
			pieces.push(ExpressionParserPiece.Prefix(cast op, parser.makePosition(startIndex)));
			parser.incrementIndex(op.op.length);
			return true;
		}
		return false;
	}

	function parseValue(): Bool {
		final startIndex = parser.getIndex();
		final value = parser.parseNextValue();
		if(value != null) {
			pieces.push(ExpressionParserPiece.Value(value));
			return true;
		}
		return false;
	}

	function parseSuffixOrCall(): Bool {
		if(!parseSuffix()) {
			return parseCall();
		}
		return true;
	}

	function parseSuffix(): Bool {
		final startIndex = parser.getIndex();
		final op = checkForOperators(SuffixOperators);
		if(op != null) {
			pieces.push(ExpressionParserPiece.Suffix(cast op, parser.makePosition(startIndex)));
			parser.incrementIndex(op.op.length);
			return true;
		}
		return false;
	}

	function parseCall(): Bool {
		final startIndex = parser.getIndex();
		final op: CallOperator = cast checkForOperators(cast CallOperators);
		if(op != null) {
			parser.incrementIndex(op.op.length);

			final exprs: Array<Expr> = [];
			while(true) {
				final exprParser = new ExpressionParser(parser, false, [",", op.opEnd]);
				if(exprParser.successful()) {
					final result = exprParser.buildExpression();
					if(result != null) {
						exprs.push(result);
					}
					if(op.opEnd == exprParser.foundString) {
						break;
					} else if(exprParser.foundString != null) {
						parser.incrementIndex(exprParser.foundString.length);
						parser.parseWhitespaceOrComments();
					}
				} else {
					break;
				}
			}

			parser.incrementIndex(op.opEnd.length);
			pieces.push(ExpressionParserPiece.Call(op, exprs, parser.makePosition(startIndex)));

			return true;
		}
		return false;
	}

	function parseInfix(): Bool {
		final startIndex = parser.getIndex();
		final op = checkForOperators(InfixOperators);
		if(op != null) {
			pieces.push(ExpressionParserPiece.Infix(cast op, parser.makePosition(startIndex)));
			parser.incrementIndex(op.op.length);
			return true;
		}
		return false;
	}

	function checkForOperators(operators: Array<Operator>): Null<Operator> {
		var opLength = 0;
		var result: Null<Operator> = null;
		for(op in operators) {
			if(parser.checkAhead(op.op)) {
				if(opLength < op.op.length) {
					opLength = op.op.length;
					result = op;
				}
			}
		}
		return result;
	}

	public function buildExpression(): Null<Expr> {
		var parts = pieces.copy();
		var error = false;
		var errorThreshold = 0;
		while(parts.length > 1) {
			final currSize = parts.length;
			final index = getNextOperatorIndex(parts);
			if(index != null) {
				final removedPiece = removeFromArray(parts, index);
				if(removedPiece == null) {
					error = true;
					break;
				}
				switch(removedPiece) {
					case Prefix(op, pos): {
						final piece = removeFromArray(parts, index);
						if(piece != null) {
							final expr = expressionPieceToExpression(piece);
							final unop = stringToUnop(op.op);
							if(expr != null && unop != null) {
								parts.insert(index, Expression({
									expr: EUnop(unop, false, expr),
									pos: pos
								}));
							} else {
								error = true;
								break;
							}
						} else {
							error = true;
							break;
						}
					}
					case Suffix(op, pos): {
						final piece = removeFromArray(parts, index - 1);
						if(piece != null) {
							final expr = expressionPieceToExpression(piece);
							final unop = stringToUnop(op.op);
							if(expr != null) {
								parts.insert(index, Expression({
									expr: EUnop(unop, true, expr),
									pos: pos
								}));
							} else {
								error = true;
								break;
							}
						} else {
							error = true;
							break;
						}
					}
					case Call(op, params, pos): {
						final piece = removeFromArray(parts, index - 1);
						if(piece != null) {
							final expr = expressionPieceToExpression(piece);
							final haxeExpr = if(expr != null) {
								if(op.op == "(") {
									{
										expr: ECall(expr, params),
										pos: pos
									}
								} else {
									null;
								}
							} else {
								null;
							}
							if(haxeExpr != null) {
								parts.insert(index - 1, Expression(haxeExpr));
							} else {
								error = true;
								break;
							}
						} else {
							error = true;
							break;
						}
					}
					case Infix(op, pos): {
						final lpiece = removeFromArray(parts, index - 1);
						final rpiece = removeFromArray(parts, index - 1);
						if(lpiece != null && rpiece != null) {
							final lexpr = expressionPieceToExpression(lpiece);
							final rexpr = expressionPieceToExpression(rpiece);
							final binop = stringToBinop(op.op);
							if(lexpr != null && rexpr != null && binop != null) {
								parts.insert(index - 1, Expression({
									expr: EBinop(binop, lexpr, rexpr),
									pos: pos
								}));
							} else {
								error = true;
								break;
							}
						} else {
							error = true;
							break;
						}
					}
					default: {}
				}
			} else {
				error = true;
				break;
			}

			if(currSize == parts.length) {
				if(++errorThreshold > 10) {
					error = true;
					break;
				} else {
					errorThreshold = 0;
				}
			}
		}
		if(error) {
			// TODO
			//Error.addError(CouldNotConstructExpression, parser, startingIndex);
			return null;
		} else if(parts.length == 1) {
			return expressionPieceToExpression(parts[0]);
		}
		return null;
	}

	function removeFromArray(arr: Array<ExpressionParserPiece>, index: Int): Null<ExpressionParserPiece> {
		if(index >= 0 && index < arr.length) {
			return arr.splice(index, 1)[0];
		}
		return null;
	}

	function expressionPieceToExpression(piece: ExpressionParserPiece): Null<Expr> {
		return switch(piece) {
			case Value(expression) | Expression(expression): expression;
			case _: null;
		}
	}

	function getNextOperatorIndex(parts: Array<ExpressionParserPiece>): Null<Int> {
		var nextOperatorIndex: Null<Int> = null;
		var nextOperatorPriority = -0xffff;
		for(i in 0...parts.length) {
			final piece = parts[i];
			final priority = getPiecePriority(piece);
			final reverse = isPieceReversePriority(piece);
			if(priority > nextOperatorPriority || (priority == nextOperatorPriority && reverse)) {
				nextOperatorIndex = i;
				nextOperatorPriority = priority;
			}
		}
		return nextOperatorIndex;
	}

	function getPiecePriority(piece: ExpressionParserPiece): Int {
		switch(piece) {
			case Prefix(op, pos): {
				return op.priority;
			}
			case Suffix(op, pos): {
				return op.priority;
			}
			case Infix(op, pos): {
				return op.priority;
			}
			case Call(op, params, pos): {
				return op.priority;
			}
			default: {
				return 0;
			}
		}
	}

	function isPieceReversePriority(piece: ExpressionParserPiece): Bool {
		switch(piece) {
			case Prefix(_): {
				return true;
			}
			default: {}
		}
		return false;
	}

	function stringToUnop(s: String): Null<Unop> {
		return switch(s) {
			case "++": OpIncrement;
			case "--": OpDecrement;
			case "-": OpNeg;
			case "!": OpNot;
			case "~": OpNegBits;
			case _: null;
		}
	}

	function stringToBinop(s: String): Null<Binop> {
		return switch(s) {
			case "+": OpAdd;
			case "*": OpMult;
			case "/": OpDiv;
			case "-": OpSub;
			case "=": OpAssign;
			case "==": OpEq;
			case "!=": OpNotEq;
			case ">": OpGt;
			case ">=": OpGte;
			case "<": OpLt;
			case "<=": OpLte;
			case "&": OpAnd;
			case "|": OpOr;
			case "^": OpXor;
			case "&&": OpBoolAnd;
			case "||": OpBoolOr;
			case "<<": OpShl;
			case ">>": OpShr;
			case ">>>": OpUShr;
			case "%": OpMod;
			case "+=": OpAssignOp(OpAdd);
			case "-=": OpAssignOp(OpSub);
			case "/=": OpAssignOp(OpDiv);
			case "*=": OpAssignOp(OpMult);
			case "<<=": OpAssignOp(OpShl);
			case ">>=": OpAssignOp(OpShr);
			case ">>>=": OpAssignOp(OpUShr);
			case "|=": OpAssignOp(OpOr);
			case "&=": OpAssignOp(OpAnd);
			case "^=": OpAssignOp(OpXor);
			case "%=": OpAssignOp(OpMod);
			case "...": OpInterval;
			case "=>": OpArrow;
			case "in": OpIn;
			case _: null;
		}
	}
}

#end
