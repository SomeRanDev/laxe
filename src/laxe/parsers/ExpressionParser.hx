package laxe.parsers;

#if (macro || laxeRuntime)

import haxe.macro.Expr;
import haxe.macro.Context;

import laxe.types.Tuple;

import laxe.parsers.Parser;

import laxe.ast.MacroManager.MacroPointer;
import laxe.ast.Operators.Operator;
import laxe.ast.Operators.PrefixOperators;
import laxe.ast.Operators.InfixOperators;
import laxe.ast.Operators.SuffixOperators;
import laxe.ast.Operators.IntervalOperator;

import laxe.stdlib.LaxeExpr;

@:nullSafety(Strict)
class ExpressionParser {
	static var macroReifReplacements: Array<Map<String, String>> = [];
	static var macroReifReplacer: Null<Map<String, String>> = null;

	static function initReifReplacer() {
		macroReifReplacer = [];
		macroReifReplacements.push(macroReifReplacer);
	}

	static function endReifReplacer() {
		final result = macroReifReplacer;
		macroReifReplacer = if(macroReifReplacements.length > 0) {
			macroReifReplacements.pop();
		} else {
			null;
		};
		return result;
	}

	static function stringToUnop(s: String): Null<Unop> {
		return switch(s) {
			case "++": OpIncrement;
			case "--": OpDecrement;
			case "-": OpNeg;
			case "!" | "not": OpNot;
			case "~": OpNegBits;
			case "...": OpSpread;
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
			case "&&" | "and": OpBoolAnd;
			case "||" | "or": OpBoolOr;
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
		if(firstCharCode >= 48 && firstCharCode <= 57) {
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
			if(op.check(parser)) {
				if(opLength < op.op.length) {
					opLength = op.op.length;
					result = op;
				}
			}
		}
		return result;
	}

	static function exprNoColon(p: Parser): Expr {
		if(!p.allowColonExpr) return expr(p);
		p.setAllowColonExpr(false);
		final result = expr(p);
		p.setAllowColonExpr(true);
		return result;
	}

	public static function expr(p: Parser, disallowColonExpr: Bool = false): Expr {
		p.pushExprDepth();
		final result = maybeExpr(p);
		p.popExprDepth();
		if(result != null) {
			return result;
		}
		p.error("Invalid expression", p.herePosition());
		return p.nullExpr();
	}

	public static function maybeExpr(p: Parser): Null<Expr> {
		p.parseWhitespaceOrComments();

		p.syncExprLineNumber();
		p.syncExprLineIndent();

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
						p.addExprDecorPointer(decor);
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
		// * Template Expressions
		// ***************************************
		if(p.allowColonExpr) {
			final save = p.saveParserState();
			final macroIdent = p.tryParseIdent("template");
			if(macroIdent != null) {
				final exprIdent = p.tryParseIdent("expr");
				if(exprIdent != null) {
					final startTemplateIndex = p.getIndex();

					initReifReplacer();
					p.startTemplate();
					var le: LaxeExpr = p.parseBlock();
					p.endTemplate();
					final replacements = endReifReplacer();

					switch(le.expr) {
						case EBlock(exprs): {
							if(exprs.length == 1) {
								le = exprs[0];
							}
						}
						case _:
					}
					final pos = Context.makePosition({ file: p.filePath, min: 0, max: 0});

					final haxeStr = le.toHaxeString();

					// Instead of trying to find a one-size-fits-all regex,
					// we track the required replacements using "reifReplacers".
					// A bit of a hack, but it works.
					//final haxeMacroStr = ~/@__dollar_(\w+)__\(([\w\d, ]+)\) 0/ig.replace(haxeStr, "$$$1{$2}");

					var haxeMacroStr = haxeStr;
					for(check => replace in replacements) {
						haxeMacroStr = StringTools.replace(haxeMacroStr, check, replace);
					}

					final reifExpr = Context.parse("macro " + haxeMacroStr, pos);
					convertTemplatePositions(reifExpr, p.filePath, startTemplateIndex);
					return reifExpr;
				} else {
					final typeIdent = p.tryParseIdent("type");
					if(typeIdent != null) {
						p.findAndParseNextContent(":");
						final startTemplateIndex = p.getIndex();
						p.startTemplate();
						var path: ComplexType = p.parseNextType();
						p.endTemplate();
						if(path != null) {
							final pos = Context.makePosition({ file: p.filePath, min: 0, max: 0});
							final reifExpr = Context.parse("macro : " + haxe.macro.ComplexTypeTools.toString(path), pos);
							convertTemplatePositions(reifExpr, p.filePath, startTemplateIndex);
							return reifExpr;
						} else {
							p.errorHere("Expected type path");
						}
					} else {
						p.restoreParserState(save);
					}
				}
			}
		}

		// ***************************************
		// * Variable initialization
		// ***************************************
		{
			final varIdent = p.tryParseOneIdent("var", "const");
			if(varIdent != null) {
				var positionUnwrap = false;
				if(p.findAndParseNextContent("(")) {
					positionUnwrap = true;
				}

				var namedUnwrap = false;
				if(p.findAndParseNextContent("{")) {
					namedUnwrap = true;
				}

				final varNames = [];
				final varTypes = [];

				while(true) {
					final varName = p.parseNextIdent();
					if(StringTools.startsWith(varName.ident, "__unwrap")) {
						p.error("Identifiers that start with '__unwrap' are reserved", varName.pos);
					} else if(varName != null) {
						final type = if(p.findAndParseNextContent(":")) {
							p.parseNextType();
						} else {
							null;
						}

						varNames.push(varName);
						varTypes.push(type);
					} else {
						p.error("Expected variable name", p.herePosition());
					}

					if(p.findAndParseNextContent(",")) {
						continue;
					} else {
						break;
					}
				}

				if(positionUnwrap) {
					if(!p.findAndParseNextContent(")")) {
						p.errorHere("')' expected");
					}
				}
				if(namedUnwrap) {
					if(!p.findAndParseNextContent("}")) {
						p.errorHere("'}' expected");
					}
				}

				if(!positionUnwrap && !namedUnwrap && varNames.length > 1) {
					positionUnwrap = true;
				}

				{

					final e = if(p.findAndParseNextContent("=")) {
						expr(p);
					} else {
						null;
					}

					final pos = p.makePosition(startIndex);

					if(e == null && (positionUnwrap || namedUnwrap)) {
						p.error("Variable unwrap must have assignment", pos);
					}

					return if(varNames.length == 0) {
						p.error("Missing variable name", pos);
						macro null;
					} else if(!positionUnwrap && !namedUnwrap) {
						{
							expr: EVars([
								{
									type: varTypes[0],
									name: varNames[0].ident,
									expr: e,
									isFinal: varIdent.ident == "const"
								}
							]),
							pos: pos
						};
					} else {
						final valueHolder = "__unwrap" + p.getUnwrapId();

						final vars = [
							{
								type: null,
								name: valueHolder,
								expr: e,
								isFinal: true
							}
						];

						var index = 0;
						for(name in varNames) {
							final i = index++;
							final n = name.ident;
							if(positionUnwrap && n == "_") {
								continue;
							}
							final compName = "component" + i;
							vars.push({
								type: varTypes[i],
								name: n,
								expr: namedUnwrap ? macro $i{valueHolder}.$n : macro $i{valueHolder}.$compName(),
								isFinal: varIdent.ident == "const"
							});
						}

						{
							expr: EVars(vars),
							pos: pos
						};
					}
				}
			}
		}

		// ***************************************
		// * Block expression
		// ***************************************
		if(p.allowColonExpr) {
			final block = p.tryParseIdent("block");
			if(block != null) {
				return p.parseBlock();
			}
		}

		// ***************************************
		// * If expression
		// ***************************************
		if(p.allowColonExpr) {
			final ifkey = p.tryParseIdent("if");
			final ifIndent = p.getIndent();
			if(ifkey != null) {
				final cond = exprNoColon(p);
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
								final eicond = exprNoColon(p);
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
		if(p.allowColonExpr) {
			final forKey = p.tryParseIdent("for");
			if(forKey != null) {
				final cond = exprNoColon(p);
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
		if(p.allowColonExpr) {
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
		if(p.allowColonExpr) {
			final runonceKey = p.tryParseIdent("runonce");
			final whileKey = p.tryParseIdent("while");
			if(whileKey != null) {
				final cond = exprNoColon(p);
				final block = p.parseBlock();
				return {
					expr: EWhile(cond, block, runonceKey == null),
					pos: p.mergePos(whileKey.pos, block.pos)
				};
			} else if(runonceKey != null) {
				p.errorHere("Expected 'while'");
			}
		}

		// ***************************************
		// * Switch expression
		// ***************************************
		if(p.allowColonExpr) {
			final switchKey = p.tryParseIdent("switch");
			final switchIndent = p.getIndent();
			if(switchKey != null) {
				final cond = exprNoColon(p);
				var caseIndent = null;

				final cases = [];

				if(p.findAndParseNextContent(":")) {
					while(true) {
						if(p.ended) {
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

								// Pattern matching gets messed up when the raw strings are type-checked.
								// So when parsing cases, we do not cast raw strings to laxe-strings.
								p.setCastStringsToLaxe(false);

								final values = [exprNoColon(p)];
								while(true) {
									if(p.findAndParseNextContent("|")) {
										values.push(exprNoColon(p));
									} else {
										break;
									}
								}

								p.setCastStringsToLaxe(true);

								final guard = if(p.tryParseIdent("if") != null) {
									exprNoColon(p);
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
		if(p.allowColonExpr) {
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
					pos: e != null ? (p.mergePos(returnKey.pos, e.pos)) : (returnKey.pos)
				};
			}
		}

		// ***************************************
		// * Cast expression
		// ***************************************
		{
			final castKey = p.tryParseIdent("cast");
			if(castKey != null) {
				final e = expr(p);
				return {
					expr: ECast(e, null),
					pos: p.mergePos(castKey.pos, e.pos)
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
		// * Function
		// ***************************************
		{
			final defKey = p.tryParseIdent("def");
			if(defKey != null) {
				final func = p.parseFunctionAfterDef();
				return {
					expr: EFunction(func.k, func.f),
					pos: p.makePosition(startIndex)
				}
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
		final lastIndex = p.index;
		
		p.parseWhitespaceOrComments();

		// Observe the following:
		//
		// block:
		//    something
		// (1 + 2)
		//
		// This could be parsed as:
		//
		// block:
		//    something(1 + 2)
		//
		// if not careful. To avoid this, certain "post" expr
		// features are disallowed (such as call operator and suffix operators)
		// unless it's the same line OR there is additional identation.
		//
		// block:
		//    something
		//        (1 + 2) # this becomes something(1 + 2)
		//
		// block:
		//    something
		// (1 + 2) # this remains separate (1 + 2) stateament
		//
		final allowAmbiguous =
			p.exprLineNumber == p.lineNumber ||
			(p.lineIndent.length > p.exprLineIndent.length &&
			StringTools.startsWith(p.lineIndent, p.exprLineIndent));

		final noSpaceFromExpr = lastIndex == p.index;

		final startIndex = p.getIndex();

		// ***************************************
		// * Macro Reification Special Inputs
		// ***************************************
		if(p.isTemplate) {
			switch(e.expr) {
				case EConst(CIdent(c)) if(StringTools.startsWith(c, "$")): {
					if(p.parseNextContent("{")) {
						final exprs = p.parseNextExpressionList("}");
						final pos = p.makePosition(startIndex);

						final cn = c.substr(1);
						final metaName = '__dollar_${cn}__';
						final metaParams = exprs.map(e -> (e : LaxeExpr).toHaxeString()).join(", ");
						macroReifReplacer.set('@$metaName($metaParams) 0', '$$$cn{$metaParams}');

						return post_expr(p, {
							expr: EMeta({
								name: metaName,
								pos: pos,
								params: exprs
							}, macro 0),
							pos: pos
						});
					}
				}
				case _:
			}
		}

		// ***************************************
		// * OpInterval
		// ***************************************
		if(noSpaceFromExpr) {
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
		if(allowAmbiguous) {
			final suffix = checkForOperators(p, SuffixOperators);
			if(suffix != null) {
				p.incrementIndex(suffix.op.length);
				return post_expr(p, {
					expr: EUnop(stringToUnop(suffix.op), true, e),
					pos: p.makePosition(startIndex)
				});
			}
		}

		// ***************************************
		// * Call Operator
		// ***************************************
		if(allowAmbiguous && p.parseNextContent("(")) {
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
		// * Array Access Operator
		// ***************************************
		if(allowAmbiguous && p.parseNextContent("[")) {
			final exprs = p.parseNextExpressionList("]");
			final pos = p.makePosition(startIndex);

			if(exprs.length == 0) {
				p.error("Expected expression within '[ ]'", p.makePosition(startIndex));
			} else if(exprs.length == 1) {
				return post_expr(p, {
					expr: EArray(e, exprs[0]),
					pos: pos
				});
			} else {
				return post_expr(p, {
					expr: ECall(macro $e.arrayAccess, exprs),
					pos: pos
				});
			}
		}

		// ***************************************
		// * the, as, is Operators
		// ***************************************
		{
			final ident = p.tryParseOneIdent("the", "as", "is");
			if(ident != null) {
				// The "is" operator does not work with abstracts.
				// Since a couple of Laxe primitives use abstracts that wrap Haxe types,
				// we want to get the internal Haxe type.
				final isOp = ident.ident == "is";
				if(isOp) p.setUseHaxeTypesForPrims(true);

				final type = p.parseNextType();
				final pos = p.makePosition(startIndex);

				if(isOp) p.setUseHaxeTypesForPrims(false);
	
				return post_expr(p, {
					expr: if(ident.ident == "the") {
						ECheckType(e, type);
					} else if(ident.ident == "as") {
						ECast(e, type);
					} else {
						EIs(e, type);
					},
					pos: pos
				});
			}
		}

		// ***************************************
		// * Infix Operators
		// ***************************************
		final infix = checkForOperators(p, InfixOperators);
		if(infix != null) {
			p.incrementIndex(infix.op.length);
			final nextExpr = expr(p);
			return post_expr(p, addInfixToExpr(infix, p.makePosition(startIndex), e, nextExpr, p));
		}

		// ***************************************
		// * Macro Call Operator
		// ***************************************
		if(allowAmbiguous && noSpaceFromExpr) {
			final isScopeInput = p.exprDepth <= 1 ? p.checkAhead(":") : false;
			final scopeExpr = if(isScopeInput) {
				p.parseBlock();
			} else {
				null;
			}
			if(isScopeInput || p.parseNextContent("!")) {
				var macroIdentExpr = e;

				final exprs = if(isScopeInput) {
					switch(e.expr) {
						case ECall(callExpr, callParams): {
							macroIdentExpr = callExpr;
							callParams;
						}
						case _: [];
					}
				} else if(p.parseNextContent("(")) {
					p.parseNextExpressionList(")");
				} else {
					[];
				}
				final pos = p.makePosition(startIndex);

				var calleeExpr: Null<Expr> = null;
				var macroName: Null<StringAndPos> = null;
				var assumeExtension = false;
				function getPath(e: Expr, list: Array<StringAndPos>) {
					return switch(e.expr) {
						case EConst(CIdent(c)): {
							final pathStrAndPos = { ident: c, pos: e.pos };
							if(macroName == null) {
								macroName = pathStrAndPos;
							}
							list.push(pathStrAndPos);
							list;
						}
						case EField(e2, field): {
							final pathStrAndPos = { ident: field, pos: e.pos };
							if(macroName == null) {
								macroName = pathStrAndPos;
								calleeExpr = e2;
							}
							getPath(e2, list);
							list.push(pathStrAndPos);
							list;
						}
						case _: {
							if(calleeExpr == null) {
								calleeExpr = e;
							}
							assumeExtension = true;
							list;
						}
					}
				}

				// There are two types of macro calls.
				// Alone, or extensions.
				// i.e. myMacro!()  vs.  (1 + 2).myMacro!()
				// If the entire expression is just CIdent + EFields, we will assume it's a direct macro call.
				// Otherwise, we assume it's an extension call.

				var pathMembers = getPath(macroIdentExpr, []);

				var resultExpr = if(isScopeInput && macroName == null) {
					pathMembers = [];
					e;
				} else if(assumeExtension) {
					pathMembers = [macroName];
					calleeExpr;
				} else {
					e;
				}

				if(isScopeInput) {
					resultExpr = e;
				}

				final mp = new MacroPointer(
					TypeParser.convertIdentListToTypePath(p, pathMembers),
					pos,
					exprs,
					calleeExpr,
					assumeExtension,
					isScopeInput ? scopeExpr : null
				);
				mp.setExpr(resultExpr);
				p.addExprMacroPointer(mp);

				return post_expr(p, resultExpr);
			}
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

	static function convertTemplatePositions(originalExpr: Expr, fp: String, startTemplateIndex: Int): Expr {
		function map(e: Expr): Expr {
			switch(e.expr) {
				case EObjectDecl(fields): {
					for(field in fields) {
						if(field.field == "pos") {
							switch(field.expr.expr) {
								case EObjectDecl(fields2): {
									for(f2 in fields2) {
										if(f2.field == "file") {
											f2.expr = macro $v{fp};
										} else if(f2.field == "min" || f2.field == "max") {
											var num = -1;
											switch(f2.expr.expr) {
												case EConst(CInt(n)): {
													num = Std.parseInt(n);
												}
												case _:
											}
											if(num != -1) {
												final newIndex = startTemplateIndex + num;
												f2.expr = macro $v{newIndex};
											}
											
										}
									}
								}
								case _:
							}
						}
					}
				}
				case _:
			}
			return haxe.macro.ExprTools.map(e, map);
		}

		return map(originalExpr);
	}
}

#end
