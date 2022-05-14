package laxe.ast;

import haxe.macro.Expr;
import haxe.macro.Context;

@:nullSafety(Strict)
@:exclude
@:forward
abstract ExprEx(Expr) from Expr to Expr {
	public function new(e: Expr) { this = e; }
	public function toString() { return haxe.macro.ExprTools.toString(this); }

	public function traceSelf() { trace(toString()); }

	public static function trace(d: Dynamic) {
		trace(d);
	}

	public static function fromString(s: String, pos: Null<Position> = null): ExprEx {
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

	public static function fromHaxeString(s: String): ExprEx {
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
