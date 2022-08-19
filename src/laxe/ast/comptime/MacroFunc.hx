package laxe.ast.comptime;

#if (macro || laxeRuntime)

import laxe.ast.comptime.CompTimeFunc;

import laxe.ast.MacroManager.MacroPointer;

import haxe.macro.Expr;
import haxe.macro.Context;

@:nullSafety(Strict)
class MacroFunc extends CompTimeFunc {
	var expr: Null<Expr>;
	var retType: Null<ComplexType>;
	var pos: Position;

	var isStringReturn: Bool;

	var func: () -> Dynamic;

	public function new(p: laxe.parsers.Parser, name: String, expr: Null<Expr>, retType: Null<ComplexType>, arguments: Null<Array<FunctionArgAndPositions>>, metadata: laxe.parsers.Parser.Metadata, pos: Position) {
		super(p, name, arguments, metadata);

		this.expr = expr;
		this.retType = retType;
		this.pos = pos;

		verifyReturnType();
		makeCallable();
	}

	override function metaType() {
		return "macro";
	}

	function verifyReturnType() {
		return switch(retType) {
			case TPath({ name: "String", pack: [], sub: null }): {
				isStringReturn = true;
				true;
			}
			case TPath({ pack: ["haxe", "macro"], name: "Expr", sub: null }) |
				TPath({ pack: ["laxe", "ast"], name: "LaxeExpr", sub: null }): {
				isStringReturn = false;
				true;
			}
			case _: {
				error("Macro functions must explicitly have a return type of either expr` or str", pos);
				false;
			}
		}
	}

	function makeCallable() {
		final fun: Function = {
			args: hasArguments ? arguments.map(argAndPos -> argAndPos.arg) : [],
			ret: retType,
			expr: expr
		};

		final funcExpr = {
			expr: EFunction(FNamed(name, false), fun),
			pos: pos
		};

		func = Eval.exprToFunction(funcExpr);
	}

	public function call(mPointer: MacroPointer): Null<Expr> {
		return if(func == null) {
			null;
		} else if(hasArguments) {
			final args = convertArguments(mPointer.params, mPointer.pos);
			Reflect.callMethod(null, func, args);
		} else {
			final result: Null<Dynamic> = func();
			if(Std.isOfType(result, String)) {
				laxe.ast.LaxeExpr.fromString(result);
			} else {
				result;
			}
		}
	}
}

#end
