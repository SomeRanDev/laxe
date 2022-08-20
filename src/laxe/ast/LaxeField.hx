package laxe.ast;

import haxe.macro.Expr.ComplexType;
import haxe.macro.Expr.Field;

@:nullSafety(Strict)
@:forward
@:remove
abstract LaxeField(Field) from Field to Field {
	public inline function new(f: Field) {
		this = f;
	}

	public function getExpr(): Null<LaxeExpr> {
		return switch(this.kind) {
			case FVar(_, e): e;
			case FFun({ expr: e }): e;
			case FProp(_, _, _, e): e;
		}
	}

    public inline function setExpr(e: LaxeExpr): Void {
        this.kind = switch(this.kind) {
            case FVar(t, _): FVar(t, e);
			case FFun(fun): {
                fun.expr = e;
                FFun(fun);
            }
			case FProp(get, set, t, _): FProp(get, set, t, e);
        }
    }

	public function isVar(): Bool {
		return switch(this.kind) {
			case FVar(_, _): true;
			case _: false;
		}
	}

    public function getVarType(): Null<ComplexType> {
        return switch(this.kind) {
			case FVar(t, _): t;
			case _: null;
		}
    }

	public function isFunction(): Bool {
		return switch(this.kind) {
			case FFun(_): true;
			case _: false;
		}
	}

    public function getFunctionReturnType(): Null<ComplexType> {
        return switch(this.kind) {
			case FFun({ ret: t }): t;
			case _: null;
		}
    }

    public function isProperty(): Bool {
		return switch(this.kind) {
			case FProp(_, _, _, _): true;
			case _: false;
		}
	}
}
