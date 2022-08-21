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

	public var isStringReturn(default, null): Bool;
	public var isExtension(default, null): Bool;

	var func: () -> Dynamic;

	public function new(p: laxe.parsers.Parser, name: String, expr: Null<Expr>, retType: Null<ComplexType>, arguments: Null<Array<FunctionArgAndPositions>>, metadata: laxe.parsers.Parser.Metadata, pos: Position) {
		super(p, name, arguments, metadata);

		this.expr = expr;
		this.retType = retType;
		this.pos = pos;

		checkIsExtension();
		verifyReturnType(retType);
		makeCallable();
	}

	override function metaType() {
		return "macro";
	}

	function checkIsExtension() {
		if(hasArguments) {
			final a = arguments[0];
			if(a.arg.name == "self") {
				final t = a.arg.type;
				switch(t) {
					case null | TPath({ pack: ["laxe", "ast"], name: "LaxeExpr" }): {
						isExtension = true;
					}
					case _: {
						var pos = a.typePos;
						if(pos == null) pos = a.identPos;
						error("Self argument must be of type expr`", pos);
					}
				}
			} else {
				isExtension = false;
			}
		}
	}

	function verifyReturnType(t: ComplexType): Bool {
		final result = switch(t) {
			case TPath({ name: "String", pack: [], sub: null }): {
				isStringReturn = true;
				true;
			}
			case TPath({ pack: ["haxe", "macro"], name: "Expr", sub: null }) |
				TPath({ pack: ["laxe", "ast"], name: "LaxeExpr", sub: null }): {
				isStringReturn = false;
				true;
			}
			case TPath(typePath) if(
					typePath.pack.length == 0 &&
					typePath.name == "Array" &&
					typePath.sub == null &&
					typePath.params != null &&
					typePath.params.length == 1
				): {
				switch(typePath.params[0]) {
					case TPType(t2): {
						verifyReturnType(t2);
					}
					case TPExpr(e): {
						false;
					}
				}
			}
			case _: {
				false;
			}
		}

		if(result == false) {
			error("Macro functions must explicitly have a return type of either expr`, expr`[], str, or str[]", pos);
		}

		return result;
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

	public function call(mPointer: MacroPointer, callee: Null<Expr>): Null<Expr> {
		return if(func == null) {
			null;
		} else {
			final result: Null<Dynamic> = if(hasArguments) {
				final argInput = callee == null ? mPointer.params : [callee].concat(mPointer.params);
				var args = convertArguments(argInput, mPointer.pos);
				Reflect.callMethod(null, func, args);
			} else {
				if(callee != null) {
					Reflect.callMethod(null, func, [callee]);
				} else {
					func();
				}
			}
			convertDynToExpr(result);
		}
	}

	function convertDynToExpr(d: Dynamic): Expr {
		return if(Std.isOfType(d, Array)) {
			var pos = null;
			if(pos == null) {
				pos = DecorManager.ProcessingPosition;
			}
			if(pos == null) {
				pos = Context.currentPos();
			}
			final exprArr = d.map(mem -> convertDynToExpr(mem));
			if(exprArr.contains(null)) {
				null;
			} else {
				{
					expr: EBlock(exprArr),
					pos: pos
				}
			}
		} else if(Std.isOfType(d, String)) {
			laxe.ast.LaxeExpr.fromString(d);
		} else {
			d;
		}
	}
}

#end
