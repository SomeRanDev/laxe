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
/*
@:nullSafety(Strict)
function exprToFunctionWArgs(e: Expr, arguments: Array<FunctionArg>): Dynamic {
	final newE = haxe.macro.ExprTools.map(e, convertSpecialCalls);

	final funcExpr = {
		pos: e.pos,
		expr: EFunction(FAnonymous, {
			args: arguments,
			expr: macro return $newE
		})
	}

	Context.typeof(macro laxe.ast.Eval._storeFunction2(function() return $funcExpr));
	@:nullSafety(Off) return _func;
}
*/
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
