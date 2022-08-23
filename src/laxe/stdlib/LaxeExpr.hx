package laxe.stdlib;

import haxe.macro.ComplexTypeTools;
import haxe.macro.Expr;
import haxe.macro.Context;

import laxe.ast.DecorManager;

@:nullSafety(Strict)
@:forward
@:remove
abstract LaxeExpr(Expr) from Expr to Expr {
	public function new(e: Expr) {
		this = e;
	}

	// convert to laxe code string
	public function toString(): String {
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
					'@"${s.name}"(${pStr}) ' + normalExprToString(e);
				} else {
					'@"${s.name}" ' + normalExprToString(e);
				}
			}

			case ECheckType(e, t): {
				switch [e.expr, t] {
					case [EConst(CString(s, kind)), TPath({ pack: ["laxe", "stdlib"], name: "LaxeString", sub: null })]: {
						normalExprToString(e);
					}
					case _: {
						normalExprToString(e) + " the " + ComplexTypeTools.toString(t);
					}
				}
			}
			case ECast(e, t): {
				if(t != null) {
					normalExprToString(e) + " as " + ComplexTypeTools.toString(t);
				} else {
					"cast " + normalExprToString(e);
				}
			}
			case EIs(e, t): {
				normalExprToString(e) + " is " + ComplexTypeTools.toString(t);
			}

			case _: {
				haxe.macro.ExprTools.toString(this);
			}
		}
	}

	static function normalExprToString(e: Expr): String {
		final le: LaxeExpr = e;
		return le.toString();
	}

	static function possiblyBlockToString(expr: Expr): String {
		return switch(expr.expr) {
			case EBlock(exprs): blockToString(exprs);
			case _: "\t" + normalExprToString(expr);
		}
	}

	static inline function blockToString(exprs: Array<Expr>): String {
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
	public inline function traceSelf(): Void {
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
	public static inline function fromHaxeString(s: String): LaxeExpr {
		#if macro
		return Context.parse(s, Context.currentPos());
		#else
		return {
			expr: EConst(CIdent("null")),
			pos: { file: "", min: 0, max: 0 }
		};
		#end
	}

	// convert to haxe string
	public inline function toHaxeString(): String {
		return haxe.macro.ExprTools.toString(this);
	}

	// helper functions
	public inline function unwrap(): LaxeExpr {
		return switch(this.expr) {
			case EMeta(_, e) |
				EParenthesis(e) |
				EUntyped(e): (e : LaxeExpr).unwrap();
			case _: this;
		}
	}

	public inline function subExprs(): Array<LaxeExpr> {
		return switch(this.expr) {
			case EArray(e1, e2): [e1, e2];
			case EBinop(_, e1, e2): [e1, e2];
			case EField(e, _): [e];
			case EParenthesis(e): [e];
			case EArrayDecl(values): values;
			case ECall(e, args): [e].concat(args);
			case ENew(_, args): args;
			case EUnop(_, _, e): [e];
			case EBlock(exprs): exprs;
			case EFor(cond, e): [cond, e];
			case EIf(cond, eif, eelse): eelse == null ? [cond, eif] : [cond, eif, eelse];
			case EWhile(cond, e, _): [cond, e];
			case ESwitch(e, _, _): [e];
			case ETry(e, _): [e];
			case EReturn(e): e != null ? [e] : [];
			case EUntyped(e): [e];
			case EThrow(e): [e];
			case ECast(e, _): [e];
			case EDisplay(e, _): [e];
			case ETernary(econd, eif, eelse): [econd, eif, eelse];
			case ECheckType(e, _): [e];
			case EMeta(_, e): [e];
			case EIs(e, _): [e];
			case _: [];
		}
	}

	public inline function metadata(): Array<MetadataEntry> {
		final result = [];
		var curr = this;
		while(true) {
			switch(curr.expr) {
				case EMeta(s, e): {
					result.push(s);
					curr = e;
				}
				case _: {
					break;
				}
			}
		}
		return result;
	}

	public inline function isConst(): Bool {
		return switch(this.expr) {
			case EConst(_): true;
			case _: false;
		}
	}

	public inline function getConst(): Constant {
		return switch(this.expr) {
			case EConst(c): c;
			case _: throw "Not an EConst";
		}
	}

	public inline function isConstString(): Bool {
		return switch(this.expr) {
			case EConst(CString(_)): true;
			case ECheckType({ expr: EConst(CString(_)) }, TPath({ pack: ["laxe", "stdlib"], name: "LaxeString" })): true;
			case _: false;
		}
	}

	public inline function getConstString(): String {
		return switch(this.expr) {
			case EConst(CString(s)): s;
			case ECheckType({ expr: EConst(CString(s)) }, TPath({ pack: ["laxe", "stdlib"], name: "LaxeString" })): s;
			case _: throw "Not a EConst(CString(_))";
		}
	}

	public inline function isArrayAccess(): Bool {
		return switch(this.expr) {
			case EArray(_, _): true;
			case _: false;
		}
	}

	public inline function getArrayAccess(): { e1: LaxeExpr, e2: LaxeExpr } {
		return switch(this.expr) {
			case EArray(e1, e2): { e1: e1, e2: e2 };
			case _: throw "Not an EArray";
		}
	}

	public inline function isBinop(): Bool {
		return switch(this.expr) {
			case EBinop(_, _, _): true;
			case _: false;
		}
	}

	public inline function getBinop(): { op: Binop, e1: LaxeExpr, e2: LaxeExpr } {
		return switch(this.expr) {
			case EBinop(op, e1, e2): { op: op, e1: e1, e2: e2 };
			case _: throw "Not an EBinop";
		}
	}

	public inline function isFieldAccess(): Bool {
		return switch(this.expr) {
			case EField(_, _): true;
			case _: false;
		}
	}

	public inline function getFieldAccess(): { e: LaxeExpr, field: String } {
		return switch(this.expr) {
			case EField(e, field): { e: e, field: field };
			case _: throw "Not an EField";
		}
	}

	public inline function isParenthesis(): Bool {
		return switch(this.expr) {
			case EArray(_, _): true;
			case _: false;
		}
	}

	public inline function isUnop(): Bool {
		return switch(this.expr) {
			case EUnop(_, _, _): true;
			case _: false;
		}
	}

	public inline function getUnop(): { op: Unop, postFix: Bool, e: LaxeExpr } {
		return switch(this.expr) {
			case EUnop(op, postFix, e): { op: op, postFix: postFix, e: e };
			case _: throw "Not an EUnop";
		}
	}

	public inline function isObjectDecl(): Bool {
		return switch(this.expr) {
			case EObjectDecl(_): true;
			case _: false;
		}
	}

	public inline function getObjectDecl(): Array<ObjectField> {
		return switch(this.expr) {
			case EObjectDecl(fields): fields;
			case _: throw "Not an EObjectDecl";
		}
	}

	public inline function isArrayDecl(): Bool {
		return switch(this.expr) {
			case EArrayDecl(_): true;
			case _: false;
		}
	}

	public inline function getArrayDecl(): Array<LaxeExpr> {
		return switch(this.expr) {
			case EArrayDecl(values): values;
			case _: throw "Not an EArrayDecl";
		}
	}

	public inline function isCall(): Bool {
		return switch(this.expr) {
			case ECall(_, _): true;
			case _: false;
		}
	}

	public inline function getCall(): { e: Expr, params: Array<LaxeExpr> } {
		return switch(this.expr) {
			case ECall(e, params): { e: e, params: params };
			case _: throw "Not an ECall";
		}
	}

	public inline function isNewCall(): Bool {
		return switch(this.expr) {
			case ENew(_, _): true;
			case _: false;
		}
	}

	public inline function getNewCall(): { t: TypePath, params: Array<LaxeExpr> } {
		return switch(this.expr) {
			case ENew(t, params): { t: t, params: params };
			case _: throw "Not an ENew";
		}
	}
	
	public inline function isVarDecl(): Bool {
		return switch(this.expr) {
			case EVars(_): true;
			case _: false;
		}
	}

	public inline function getVarDecl(): Array<Var> {
		return switch(this.expr) {
			case EVars(vars): vars;
			case _: throw "Not an EVars";
		}
	}

	public inline function isFunctionDecl(): Bool {
		return switch(this.expr) {
			case EFunction(_, _): true;
			case _: false;
		}
	}

	public inline function getFunctionDecl(): { kind: Null<FunctionKind>, f: Function } {
		return switch(this.expr) {
			case EFunction(kind, f): { kind: kind, f: f };
			case _: throw "Not an EFunction";
		}
	}

	public inline function isBlock(): Bool {
		return switch(this.expr) {
			case EBlock(_): true;
			case _: false;
		}
	}

	public inline function getBlock(): Array<LaxeExpr> {
		return switch(this.expr) {
			case EBlock(exprs): exprs;
			case _: throw "Not an EFunction";
		}
	}

	public inline function isFor(): Bool {
		return switch(this.expr) {
			case EFor(_, _): true;
			case _: false;
		}
	}
	
	public inline function getFor(): { it: LaxeExpr, expr: LaxeExpr } {
		return switch(this.expr) {
			case EFor(it, expr): { it: it, expr: expr };
			case _: throw "Not an EFor";
		}
	}

	public inline function isIf(): Bool {
		return switch(this.expr) {
			case EIf(_, _, _): true;
			case _: false;
		}
	}

	public inline function getIf(): { econd: LaxeExpr, eif: LaxeExpr, eelse: Null<LaxeExpr> } {
		return switch(this.expr) {
			case EIf(econd, eif, eelse): { econd: econd, eif: eif, eelse: eelse };
			case _: throw "Not an EIf";
		}
	}

	public inline function isWhile(): Bool {
		return switch(this.expr) {
			case EWhile(_, _, _): true;
			case _: false;
		}
	}

	public inline function getWhile(): { econd: LaxeExpr, e: LaxeExpr, normalWhile: Bool } {
		return switch(this.expr) {
			case EWhile(econd, e, normalWhile): { econd: econd, e: e, normalWhile: normalWhile };
			case _: throw "Not an EWhile";
		}
	}

	public inline function isSwitch(): Bool {
		return switch(this.expr) {
			case ESwitch(_, _, _): true;
			case _: false;
		}
	}

	public inline function getSwitch(): { e: LaxeExpr, cases: Array<Case>, edef: Null<LaxeExpr> } {
		return switch(this.expr) {
			case ESwitch(e, cases, edef): { e: e, cases: cases, edef: edef };
			case _: throw "Not an ESwitch";
		}
	}

	public inline function isTry(): Bool {
		return switch(this.expr) {
			case ETry(_, _): true;
			case _: false;
		}
	}

	public inline function getTry(): { e: LaxeExpr, catches: Array<Catch> } {
		return switch(this.expr) {
			case ETry(e, catches): { e: e, catches: catches };
			case _: throw "Not an ETry";
		}
	}

	public inline function isReturn(): Bool {
		return switch(this.expr) {
			case EReturn(_): true;
			case _: false;
		}
	}

	public inline function getReturn(): Null<LaxeExpr> {
		return switch(this.expr) {
			case EReturn(e): e;
			case _: throw "Not an EReturn";
		}
	}

	public inline function isBreak(): Bool {
		return switch(this.expr) {
			case EBreak: true;
			case _: false;
		}
	}

	public inline function isContinue(): Bool {
		return switch(this.expr) {
			case EContinue: true;
			case _: false;
		}
	}

	public inline function isUntyped(): Bool {
		return switch(this.expr) {
			case EUntyped(_): true;
			case _: false;
		}
	}

	public inline function getUntyped(): LaxeExpr {
		return switch(this.expr) {
			case EUntyped(e): e;
			case _: throw "Not an EUntyped";
		}
	}

	public inline function isThrow(): Bool {
		return switch(this.expr) {
			case EThrow(_): true;
			case _: false;
		}
	}

	public inline function getThrow(): LaxeExpr {
		return switch(this.expr) {
			case EThrow(e): e;
			case _: throw "Not an EThrow";
		}
	}

	public inline function isCast(): Bool {
		return switch(this.expr) {
			case ECast(_, _): true;
			case _: false;
		}
	}

	public inline function getCast(): { e: LaxeExpr, t: Null<ComplexType> } {
		return switch(this.expr) {
			case ECast(e, t): { e: e, t: t };
			case _: throw "Not an ECast";
		}
	}
	
	public inline function isDisplay(): Bool {
		return switch(this.expr) {
			case EDisplay(_, _): true;
			case EDisplayNew(_): true;
			case _: false;
		}
	}

	public inline function getDisplay(): { e: LaxeExpr, displayKind: DisplayKind } {
		return switch(this.expr) {
			case EDisplay(e, displayKind): { e: e, displayKind: displayKind };
			case _: throw "Not an EDisplay";
		}
	}
	
	public inline function isTernary(): Bool {
		return switch(this.expr) {
			case ETernary(_, _, _): true;
			case _: false;
		}
	}

	public inline function getTernary(): { econd: LaxeExpr, eif: LaxeExpr, eelse: LaxeExpr } {
		return switch(this.expr) {
			case ETernary(econd, eif, eelse): { econd: econd, eif: eif, eelse: eelse };
			case _: throw "Not an ETernary";
		}
	}

	public inline function isMeta(): Bool {
		return switch(this.expr) {
			case EMeta(_, _): true;
			case _: false;
		}
	}

	public inline function getMeta(): { s: MetadataEntry, e: LaxeExpr } {
		return switch(this.expr) {
			case EMeta(s, e): { s: s, e: e };
			case _: throw "Not an EMeta";
		}
	}

	public inline function isIs(): Bool {
		return switch(this.expr) {
			case EIs(_, _): true;
			case _: false;
		}
	}

	public inline function getIs(): { e: LaxeExpr, t: ComplexType } {
		return switch(this.expr) {
			case EIs(e, t): { e: e, t: t };
			case _: throw "Not an EIs";
		}
	}
}
