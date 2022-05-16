package laxe.ast;

import haxe.macro.Expr;
import haxe.macro.Context;

@:nullSafety(Strict)
@:exclude
@:forward
abstract LaxeExpr(Expr) from Expr to Expr {
	public function new(e: Expr) { this = e; }

	// convert to laxe code string
	public function toString() {
		return switch(this.expr) {
			case EBlock(exprs): {
				"block:\n" + blockToString(exprs);
			}
			case EIf(econd, eif, null): {
				"if " + normalExprToString(econd) + ":\n" + possiblyBlockToString(eif);
			}
			case EIf(econd, eif, eelse): {
				var result = normalExprToString({ expr: EIf(econd, eif, null), pos: this.pos });
				switch(eelse.expr) {
					case EIf(elcond, elif, elese): {
						result += "\nelse " + normalExprToString(eelse);
					}
					case _: {
						result += "\nelse:\n" + possiblyBlockToString(eelse);
					}
				}
				result;
			}
			case EWhile(econd, e, normalWhile): {
				if(normalWhile) {
					"while " + normalExprToString(econd) + ":\n" + possiblyBlockToString(e);
				} else {
					"runonce while " + normalExprToString(econd) + ":\n" + possiblyBlockToString(e);
				}
			}
			case EFor(it, expr): {
				"for " + normalExprToString(it) + ":\n" + possiblyBlockToString(expr);
			}
			case ESwitch(e, cases, edef): {
				var result = "switch " + normalExprToString(e) + ":\n";
				for(c in cases) {
					var caseStr = "case " + c.values.map(v -> normalExprToString(v)).join(" | ");
					if(c.guard != null) {
						caseStr += " if " + normalExprToString(c.guard);
					}
					caseStr += ":\n";
					if(c.expr != null) {
						caseStr += possiblyBlockToString(c.expr);
					}
					result += caseStr.split("\n").map(s -> "  " + s).join("\n") + "\n";
				}
				result;
			}
			case EMeta(s, e): {
				if(s.params != null) {
					final pStr = s.params.map(p -> normalExprToString(p)).join(", ");
					'@[${s.name}](${pStr})\n' + normalExprToString(e);
				} else {
					'@[${s.name}]\n' + normalExprToString(e);
				}
			}
			case _: {
				haxe.macro.ExprTools.toString(this);
			}
		}
	}

	static function normalExprToString(e: Expr) {
		final le: LaxeExpr = e;
		return le.toString();
	}

	static function possiblyBlockToString(expr: Expr) {
		return switch(expr.expr) {
			case EBlock(exprs): blockToString(exprs);
			case _: "\t" + normalExprToString(expr);
		}
	}

	static function blockToString(exprs: Array<Expr>) {
		var result = [];
		for(e in exprs) {
			final le: LaxeExpr = e;
			final leStr = le.toString();
			final str = leStr.split("\n").map(l -> "\t" + l).join("\n");
			result.push(str);
		}
		return result.join("\n");
	}

	// utility
	public function traceSelf() {
		trace(toString());
	}

	// parse from string
	public static function fromString(s: String, pos: Null<Position> = null): LaxeExpr {
		#if macro
		if(pos == null) {
			pos = DecorManager.ProcessingPosition;
		}
		if(pos == null) {
			pos = Context.currentPos();
		}
		final p = laxe.parsers.Parser.fromStaticPosition(s, pos);
		final e = p.parseNextExpression();
		return e;
		#else
		return {
			expr: EConst(CIdent("null")),
			pos: { file: "", min: 0, max: 0 }
		};
		#end
	}

	// parse from haxe string
	public static function fromHaxeString(s: String): LaxeExpr {
		#if macro
		return Context.parse(s, Context.currentPos());
		#else
		return {
			expr: EConst(CIdent("null")),
			pos: { file: "", min: 0, max: 0 }
		};
		#end
	}
}
