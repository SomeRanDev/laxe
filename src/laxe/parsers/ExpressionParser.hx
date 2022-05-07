package laxe.parsers;

#if (macro || laxeRuntime)
/*
import laxe.parsers.Parser;

import laxe.ast.Operators.Operator;
import laxe.ast.Operators.PrefixOperators;
import laxe.ast.Operators.InfixOperators;
import laxe.ast.Operators.SuffixOperators;

enum ExpressionParserMode {
	Prefix;
	Value;
	Suffix;
	Infix;
}

enum ExpressionParserPiece {
	Prefix(op: PrefixOperator, pos: Position);
	Value(literal: Literal, pos: Position);
	Suffix(op: SuffixOperator, pos: Position);
	Call(op: CallOperator, params: Array<Expression>, pos: Position);
	Infix(op: InfixOperator, pos: Position);
	ExpressionPlaceholder(expression: Expression);
}

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
				case Value(str, pos): trace(str);
				case Suffix(op, pos): trace(op.op);
				case Call(op, params, pos): trace(op.op + op.endOp);
				case Infix(op, pos): trace(op.op);
				case ExpressionPlaceholder(expr): trace(expr);
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
		final literal = parser.parseNextLiteral();
		if(literal != null) {
			pieces.push(ExpressionParserPiece.Value(literal, parser.makePosition(startIndex)));
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
		final op = checkForOperators(cast SuffixOperators.all());
		if(op != null) {
			pieces.push(ExpressionParserPiece.Suffix(cast op, parser.makePosition(startIndex)));
			parser.incrementIndex(op.op.length);
			return true;
		}
		return false;
	}

	function parseCall(): Bool {
		final startIndex = parser.getIndex();
		final op: CallOperator = cast checkForOperators(cast CallOperators.all());
		if(op != null) {
			parser.incrementIndex(op.op.length);

			final exprs: Array<Expression> = [];
			while(true) {
				final exprParser = new ExpressionParser(parser, false, [",", op.endOp]);
				if(exprParser.successful()) {
					final result = exprParser.buildExpression();
					if(result != null) {
						exprs.push(result);
					}
					if(op.endOp == exprParser.foundString) {
						break;
					} else if(exprParser.foundString != null) {
						parser.incrementIndex(exprParser.foundString.length);
						parser.parseWhitespaceOrComments();
					}
				} else {
					break;
				}
			}

			parser.incrementIndex(op.endOp.length);
			pieces.push(ExpressionParserPiece.Call(op, exprs, parser.makePosition(startIndex)));

			return true;
		}
		return false;
	}

	function parseInfix(): Bool {
		final startIndex = parser.getIndex();
		final op = checkForOperators(cast InfixOperators.all());
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

	public function buildExpression(): Null<Expression> {
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
							if(expr != null) {
								parts.insert(index, ExpressionPlaceholder(Prefix(op, expr, pos)));
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
							if(expr != null) {
								parts.insert(index, ExpressionPlaceholder(Suffix(op, expr, pos)));
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
							if(expr != null) {
								parts.insert(index - 1, ExpressionPlaceholder(Call(op, expr, params, pos)));
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
							if(lexpr != null && rexpr != null) {
								parts.insert(index - 1, ExpressionPlaceholder(Infix(op, lexpr, rexpr, pos)));
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
			Error.addError(CouldNotConstructExpression, parser, startingIndex);
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

	function expressionPieceToExpression(piece: ExpressionParserPiece): Null<Expression> {
		switch(piece) {
			case Value(literal, pos): return Value(literal, pos);
			case ExpressionPlaceholder(expression): return expression;
			default: {}
		}
		return null;
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
}
*/
#end
