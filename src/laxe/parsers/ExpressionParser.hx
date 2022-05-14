package laxe.parsers;

#if (macro || laxeRuntime)

import haxe.macro.Expr;
import haxe.macro.Context;

import laxe.types.Tuple;

import laxe.parsers.Parser;

import laxe.ast.DecorManager;
import laxe.ast.Operators.Operator;
import laxe.ast.Operators.PrefixOperators;
import laxe.ast.Operators.InfixOperators;
import laxe.ast.Operators.SuffixOperators;
import laxe.ast.Operators.IntervalOperator;

class ExpressionParser {
	static function stringToUnop(s: String): Null<Unop> {
		return switch(s) {
			case "++": OpIncrement;
			case "--": OpDecrement;
			case "-": OpNeg;
			case "!": OpNot;
			case "~": OpNegBits;
			case _: null;
		}
	}

	static function stringToBinop(s: String): Null<Binop> {
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

	static function isComponentAccess(fieldName: String) {
		var result = true;
		final firstCharCode = fieldName.charCodeAt(0);
		if(firstCharCode >= 49 && firstCharCode <= 57) {
			for(i in 1...fieldName.length) {
				final charCode = fieldName.charCodeAt(i);
				if(charCode < 48 || charCode > 57) {
					result = false;
					break;
				}
			}
		} else {
			result = false;
		}
		return result;
	}

	static function checkForOperators(parser: Parser, operators: Array<Operator>): Null<Operator> {
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

	public static function expr(p: Parser): Expr {
		final result = maybeExpr(p);
		if(result != null) {
			return result;
		}
		p.error("Invalid expression", p.herePosition());
		return p.nullExpr();
	}

	public static function maybeExpr(p: Parser): Null<Expr> {
		p.parseWhitespaceOrComments();

		// ***************************************
		// * Metadata and Decorators
		// ***************************************
		{
			final metadata = p.parseAllNextDecors();
			if(metadata.string != null || metadata.typed != null) {
				var currentExpr = expr(p);

				if(metadata.string != null) {
					metadata.string.reverse();
					for(entry in metadata.string) {
						currentExpr = {
							expr: EMeta(entry, currentExpr),
							pos: entry.pos
						};
					}
				}

				if(metadata.typed != null) {
					for(decor in metadata.typed) {
						decor.setExpr(currentExpr);
						p.addDecorPointer(decor);
					}
				}

				return currentExpr;
			}
		}

		final startIndex = p.getIndex();

		// ***************************************
		// * Prefix Operators
		// ***************************************
		final prefix = checkForOperators(p, PrefixOperators);
		if(prefix != null) {
			p.incrementIndex(prefix.op.length);
			final nextExpr = expr(p);
			return addPrefixToExpr(prefix, p.makePosition(startIndex), nextExpr, p);
		}

		// ***************************************
		// * Parenthesis and Tuple
		// ***************************************
		if(p.parseNextContent("(")) {
			final exprs = p.parseNextExpressionList(")");
			final pos = p.makePosition(startIndex);
			if(exprs.length == 1) {
				return post_expr(p, {
					expr: EParenthesis(exprs[0]),
					pos: pos
				});
			} else {
				return post_expr(p, Tuple.makeTupleExpr(exprs, pos));
			}
		}

		// ***************************************
		// * Variable initialization
		// ***************************************
		{
			var varIdent = p.tryParseOneIdent("var", "let", "mut");
			if(varIdent != null) {
				final varName = p.parseNextIdent();
				if(varName != null) {
					final type = if(p.findAndParseNextContent(":")) {
						p.parseNextType();
					} else {
						null;
					}

					final e = if(p.findAndParseNextContent("=")) {
						expr(p);
					} else {
						null;
					}

					final pos = p.makePosition(startIndex);
					return {
						expr: EVars([
							{
								type: type,
								name: varName.ident,
								expr: e,
								isFinal: varIdent.ident == "let"
							}
						]),
						pos: pos
					};
				} else {
					p.error("Expected variable name", p.herePosition());
				}
			}
		}

		// ***************************************
		// * Block expression
		// ***************************************
		{
			final block = p.tryParseIdent("block");
			if(block != null) {
				return p.parseBlock();
			}
		}

		// ***************************************
		// * If expression
		// ***************************************
		{
			final ifkey = p.tryParseIdent("if");
			final ifIndent = p.getIndent();
			if(ifkey != null) {
				final cond = expr(p);
				final block = p.parseBlock();

				final elseIfExpr: Array<{ cond: Expr, e: Expr, p: Position }> = [];
				var elseExpr: Null<Expr> = null;
				while(!p.ended) {
					final state = p.saveParserState();
					p.parseWhitespaceOrComments();

					var found = false;
					if(p.getIndent() == ifIndent) {
						final elseStartIndex = p.getIndex();
						final elseKey = p.tryParseOneIdent("else", "elif");
						if(elseKey != null) {
							p.parseWhitespaceOrComments();
							final elseIfKey = elseKey.ident == "elif" ? elseKey : p.tryParseIdent("if");
							if(elseIfKey != null) {
								final eicond = expr(p);
								final block = p.parseBlock();
								elseIfExpr.push({
									cond: eicond,
									e: block,
									p: p.makePosition(elseStartIndex)
								});
								found = true;
							} else {
								final block = p.parseBlock();
								elseExpr = block;
								found = true;
								break;
							}
						}
					}
					
					if(!found) {
						p.restoreParserState(state);
						break;
					}
				}
				
				var finalElseExpr = elseExpr;
				var i = (elseIfExpr.length - 1);
				while(i >= 0) {
					final curr = elseIfExpr[i];
					finalElseExpr = {
						expr: EIf(curr.cond, curr.e, finalElseExpr),
						pos: curr.p
					};
					i--;
				}

				return {
					expr: EIf(cond, block, finalElseExpr),
					pos: p.mergePos(ifkey.pos, block.pos)
				};
			}
		}

		// ***************************************
		// * For expression
		// ***************************************
		{
			final forKey = p.tryParseIdent("for");
			if(forKey != null) {
				final cond = expr(p);
				final block = p.parseBlock();
				return {
					expr: EFor(cond, block),
					pos: p.mergePos(forKey.pos, block.pos)
				};
			}
		}

		// ***************************************
		// * Loop expression
		// ***************************************
		{
			final loopKey = p.tryParseIdent("loop");
			if(loopKey != null) {
				final block = p.parseBlock();
				return {
					expr: EWhile(macro true, block, true),
					pos: p.mergePos(loopKey.pos, block.pos)
				};
			}
		}

		// ***************************************
		// * While expression
		// ***************************************
		{
			final whileKey = p.tryParseIdent("while");
			if(whileKey != null) {
				final cond = expr(p);
				final block = p.parseBlock();
				return {
					expr: EWhile(cond, block, true),
					pos: p.mergePos(whileKey.pos, block.pos)
				};
			}
		}

		// ***************************************
		// * Switch expression
		// ***************************************
		{
			final switchKey = p.tryParseIdent("switch");
			final switchIndent = p.getIndent();
			if(switchKey != null) {
				final cond = expr(p);
				var caseIndent = null;

				final cases = [];

				if(p.findAndParseNextContent(":")) {
					while(true) {
						if(p.ended) {
							p.errorHere("Unexpected end of file");
							break;
						}

						p.parseWhitespaceOrComments();
						if(caseIndent == null) {
							caseIndent = p.getIndent();
							if(!StringTools.startsWith(caseIndent, switchIndent)) {
								p.errorHere("Inconsistent indentation");
								break;
							}
						}

						if(p.tryParseIdent("case") != null) {
							if(p.getIndent() == caseIndent) {
								final values = [expr(p)];
								while(true) {
									if(p.findAndParseNextContent("|")) {
										values.push(expr(p));
									} else {
										break;
									}
								}

								final guard = if(p.tryParseIdent("if") != null) {
									expr(p);
								} else {
									null;
								}

								final expr = p.parseBlock();

								cases.push({
									values: values,
									guard: guard,
									expr: expr
								});
							} else {
								p.errorHere("Inconsistent indentation");
								break;
							}
						} else {
							break;
						}
					}
				}

				return {
					expr: ESwitch(cond, cases, null),
					pos: p.makePosition(startIndex)
				};
			}
		}

		// ***************************************
		// * Try expression
		// ***************************************
		{
			final tryKey = p.tryParseIdent("try");
			final tryIdent = p.getIndent();
			if(tryKey != null) {
				final block = p.parseBlock();
				final catches = [];
				
				while(!p.ended) {
					final state = p.saveParserState();
					p.parseWhitespaceOrComments();

					var found = false;
					if(p.getIndent() == tryIdent) {
						final catchStartIndex = p.getIndex();
						final catchKey = p.tryParseIdent("catch");
						if(catchKey != null) {
							var varName = null;
							var type = null;
							if(p.findAndParseNextContent("(")) {
								varName = p.parseNextIdent().ident;
								type = if(p.findAndParseNextContent(":")) {
									p.parseNextType();
								} else {
									null;
								}
								if(!p.findAndParseNextContent(")")) {
									p.errorHere("Expected ')'");
								}
							} else {
								varName = "e";
							}

							final expr = p.parseBlock();

							catches.push({
								name: varName,
								expr: expr,
								type: type
							});
							found = true;
						} else {
							break;
						}
					}

					if(!found) {
						p.restoreParserState(state);
						break;
					}
				}

				return {
					expr: ETry(block, catches),
					pos: p.mergePos(tryKey.pos, block.pos)
				};
			}
		}

		// ***************************************
		// * Return expression
		// ***************************************
		{
			final returnKey = p.tryParseIdent("return");
			if(returnKey != null) {
				final e = maybeExpr(p);
				return {
					expr: EReturn(e),
					pos: p.mergePos(returnKey.pos, e.pos)
				};
			}
		}

		// ***************************************
		// * Throw expression
		// ***************************************
		{
			final throwKey = p.tryParseIdent("throw");
			if(throwKey != null) {
				final e = expr(p);
				return {
					expr: EThrow(e),
					pos: p.mergePos(throwKey.pos, e.pos)
				};
			}
		}

		// ***************************************
		// * Untyped expression
		// ***************************************
		{
			final untypedKey = p.tryParseIdent("untyped");
			if(untypedKey != null) {
				final e = expr(p);
				return {
					expr: EUntyped(e),
					pos: p.mergePos(untypedKey.pos, e.pos)
				};
			}
		}

		// ***************************************
		// * Pass, break, continue expression
		// ***************************************
		{
			final ident = p.tryParseOneIdent("pass", "break", "continue");
			if(ident != null) {
				final exprDef = switch(ident.ident) {
					case "break": EBreak;
					case "continue": EContinue;
					case _: EConst(CIdent("null"));
				}
				return {
					expr: exprDef,
					pos: ident.pos
				};
			}
		}

		{
			final newKey = p.tryParseIdent("new");
			if(newKey != null) {
				final type = p.parseNextTypePath();
				return post_expr(p, {
					expr: ENew(type, []),
					pos: p.makePosition(startIndex)
				});
			}
		}

		// ***************************************
		// * Value (Ident, Int, Float, String, Array, Struture, etc.)
		// ***************************************
		final value = p.parseNextValue();
		if(value != null) {
			return post_expr(p, value);
		}

		// ***************************************
		// * If all else fails...
		// ***************************************
		return null;
	}
	
	static function post_expr(p: Parser, e: Expr): Expr {
		p.parseWhitespaceOrComments();

		final startIndex = p.getIndex();

		// ***************************************
		// * OpInterval
		// ***************************************
		{
			if(p.findAndParseNextContent("...")) {
				final nextExpr = expr(p);
				return addInfixToExpr(IntervalOperator, p.makePosition(startIndex), e, nextExpr, p);
			}
		}

		// ***************************************
		// * Field Access
		// ***************************************
		{
			final dot = #if (haxe_ver >= 4.3) p.checkAhead("?.") ? 2 : #end (p.checkAhead(".") ? 1 : 0);
			if(dot > 0) {
				p.incrementIndex(dot);

				#if (haxe_ver >= 4.3)
				final accessType = dot == 2 ? EFSafe : EFNormal;
				#end

				final fieldName = p.parseNextIdentMaybeNumberStartOrElse();
				final pos = p.mergePos(e.pos, fieldName.pos);

				if(isComponentAccess(fieldName.ident)) {
					final accessExpr = {
						expr: EField(e, "component" + fieldName.ident #if (haxe_ver >= 4.3) , accessType #end),
						pos: pos
					};
					return post_expr(p, {
						expr: ECall(accessExpr, []),
						pos: pos
					});
				}

				return post_expr(p, {
					expr: EField(e, fieldName.ident #if (haxe_ver >= 4.3) , accessType #end),
					pos: pos
				});
			}
		}

		// ***************************************
		// * Suffix Operators
		// ***************************************
		final suffix = checkForOperators(p, SuffixOperators);
		if(suffix != null) {
			p.incrementIndex(suffix.op.length);
			return post_expr(p, {
				expr: EUnop(stringToUnop(suffix.op), true, e),
				pos: p.makePosition(startIndex)
			});
		}

		// ***************************************
		// * Call Operator
		// ***************************************
		if(p.parseNextContent("(")) {
			final exprs = p.parseNextExpressionList(")");
			final pos = p.makePosition(startIndex);

			switch(e.expr) {
				case ENew(t, params): {
					return post_expr(p, {
						expr: EParenthesis({
							expr: ENew(t, params.concat(exprs)),
							pos: e.pos
						}),
						pos: pos
					});
				}
				case _:
			}

			return post_expr(p, {
				expr: ECall(e, exprs),
				pos: pos
			});
		}

		// ***************************************
		// * Infix Operators
		// ***************************************
		final infix = checkForOperators(p, InfixOperators);
		if(infix != null) {
			p.incrementIndex(infix.op.length);
			final nextExpr = expr(p);
			return addInfixToExpr(infix, p.makePosition(startIndex), e, nextExpr, p);
		}

		// ***************************************
		// * If all else fails...
		// ***************************************
		return e;
	}

	static function addInfixToExpr(o: Operator, op: Position, e1: Expr, e2: Expr, p: Parser): Expr {
		switch(e2.expr) {
			case EBinop(binop, be1, be2): {
				var leftPriority = o.priority;
				var rightPriority = 0;
				for(i in InfixOperators) {
					if(stringToBinop(i.op) == binop) {
						rightPriority = i.priority;
						break;
					}
				}

				if(leftPriority >= rightPriority) {
					final leftExpr = addInfixToExpr(o, op, e1, be1, p);
					return {
						expr: EBinop(binop, leftExpr, be2),
						pos: p.mergePos(leftExpr.pos, be2.pos)
					};
				}
			}
			case _:
		}

		return {
			expr: EBinop(stringToBinop(o.op), e1, e2),
			pos: p.mergePos(e1.pos, e2.pos)
		};
	}

	static function addPrefixToExpr(o: Operator, op: Position, e: Expr, p: Parser): Expr {
		final exprDef = switch(e.expr) {
			case EBinop(binop, e1, e2): EBinop(binop, addPrefixToExpr(o, op, e1, p), e2);
			case ETernary(econd, eif, eelse): ETernary(addPrefixToExpr(o, op, econd, p), eif, eelse);
			case EIs(eis, t): EIs(addPrefixToExpr(o, op, eis, p), t);
			case _: EUnop(stringToUnop(o.op), false, e);
		}

		return {
			expr: exprDef,
			pos: p.mergePos(op, e.pos)
		};
	}
}

#end
