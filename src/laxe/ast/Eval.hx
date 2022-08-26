package laxe.ast;

// Based on technique from tink.Exprs.eval
// https://github.com/haxetink/tink_macro
//
// https://github.com/haxetink/tink_macro/blob/master/LICENSE
// The MIT License (MIT)
//
// Copyright (c) 2013 Juraj Kirchheim
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of
// this software and associated documentation files (the "Software"), to deal in
// the Software without restriction, including without limitation the rights to
// use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
// the Software, and to permit persons to whom the Software is furnished to do so,
// subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
// FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
// COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
// IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
// CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

import haxe.macro.Expr;

#if (macro || laxeRuntime)

import haxe.macro.Context;

// This eval hack is unable to run `trace` normally.
// So instead, instances of `trace` are replaced with the `evalTrace` function.
@:nullSafety(Strict)
function convertSpecialCalls(e: Expr) {
	switch(e.expr) {
		case ECall({ expr: EConst(CIdent("trace")), pos: p }, params): {
			// get new identifier for trace
			final p = e.pos;
			final ident = macro @:pos(p) laxe.ast.Eval.evalTrace;

			// add pos infos to past parameter
			final v = Context.getPosInfos(e.pos);
			params.push(macro $v{v});

			// generate new expression
			return {
				expr: ECall(ident, params),
				pos: e.pos
			}
		}

		#if laxe.meta.UseEvalMath
		case ECall({
			expr: EField({ expr: EConst(CIdent("Math")) }, fieldName),
			pos: p
		}, params) if(EvalMath.names.contains(fieldName)): {
			final p = e.pos;
			final ident = macro @:pos(p) laxe.ast.Eval.EvalMath.$fieldName;
			return {
				expr: ECall(ident, params),
				pos: e.pos
			}
		}
		#end

		case ECall({
			expr: EField({
				expr: EField(e, "Context"),
				pos: p1
			}, funcName), pos: p2
		}, params): {
			// get new identifier for makeExpr
			final p = e.pos;
			final ident = if(funcName == "makeExpr") {
				macro @:pos(p) laxe.ast.Eval.evalMakeExpr;
			} else if(funcName == "makePosition") {
				macro @:pos(p) laxe.ast.Eval.evalMakePosition;
			} else {
				null;
			}

			final newParams = params.map(p -> convertSpecialCalls(p));

			// generate new expression
			if(ident != null) {
				return {
					expr: ECall(ident, newParams),
					pos: e.pos
				}
			}
		}
		case _:
	}
	return haxe.macro.ExprTools.map(e, convertSpecialCalls);
}

@:nullSafety(Strict)
function exprToFunction(e: Expr): Dynamic {
	final newE = haxe.macro.ExprTools.map(e, convertSpecialCalls);
	Context.typeof(macro laxe.ast.Eval._storeFunction(function() return $newE));
	@:nullSafety(Off) return _func;
}

#end

@:exclude var _func: Null<Dynamic> = null;

@:nullSafety(Strict)
@:exclude
macro function _storeFunction(f: () -> (() -> Void)) {
	_func = f();
	return macro null;
}

@:nullSafety(Strict)
@:exclude
function evalTrace(d: Dynamic, pos: Null<{ file: String, min: Int, max: Int }> = null) {
	#if macro
	final prefix = if(pos != null) {
		var loc = haxe.macro.PositionTools.toLocation(Context.makePosition(pos));
		loc.file + ":" + loc.range.start.line;
	} else {
		"";
	}
	
	final s = Std.string(d);
	haxe.Log.trace('${prefix}: $s', null);
	#else
	trace(d);
	#end
}

@:nullSafety(Strict)
@:exclude
function evalMakeExpr(v: Dynamic, p: Position): Expr {
	#if macro
	return Context.makeExpr(v, p);
	#else
	return {
		expr: EConst(CIdent("0")),
		pos: p
	};
	#end
}

@:nullSafety(Strict)
@:exclude
function evalMakePosition(inf: { min: Int, max: Int, file: String }): Position {
	#if macro
	return Context.makePosition(inf);
	#else
	return inf;
	#end
}

@:nullSafety(Strict)
@:exclude
inline function sanitizePositions(e: { expr: haxe.macro.Expr.ExprDef, pos: Dynamic }) {
	#if macro
	return {
		expr: e.expr,
		pos: Context.makePosition(e.pos)
	};
	#else
	return e;
	#end
}

#if laxe.meta.UseEvalMath
@:nullSafety(Strict)
@:exclude
class EvalMath {
	public static var names = [
		"abs", "acos", "asin", "atan", "atan2", "ceil",
		"cos", "exp", "fceil", "ffloor", "floor", "fround",
		"isFinite", "isNaN", "log", "max", "min", "pow", "random",
		"round", "sin", "sqrt", "tan"
	];
	public static function abs(v) return Math.abs(v);
	public static function acos(v) return Math.acos(v);
	public static function asin(v) return Math.asin(v);
	public static function atan(v) return Math.atan(v);
	public static function atan2(y,x) return Math.atan2(y,x);
	public static function ceil(v) return Math.ceil(v);
	public static function cos(v) return Math.cos(v);
	public static function exp(v) return Math.exp(v);
	public static function fceil(v) return Math.fceil(v);
	public static function ffloor(v) return Math.ffloor(v);
	public static function floor(v) return Math.floor(v);
	public static function fround(v) return Math.fround(v);
	public static function isFinite(v) return Math.isFinite(v);
	public static function isNaN(v) return Math.isNaN(v);
	public static function log(v) return Math.log(v);
	public static function max(a,b) return Math.max(a,b);
	public static function min(a,b) return Math.min(a,b);
	public static function pow(v,u) return Math.pow(v,u);
	public static function random() return Math.random();
	public static function round(v) return Math.round(v);
	public static function sin(v) return Math.sin(v);
	public static function sqrt(v) return Math.sqrt(v);
	public static function tan(v) return Math.tan(v);
}
#end
