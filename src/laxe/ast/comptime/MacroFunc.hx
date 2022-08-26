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
	public var isScopable(default, null): Bool;

	var func: () -> Dynamic;

	public function new(p: laxe.parsers.Parser, name: String, expr: Null<Expr>, retType: Null<ComplexType>, arguments: Null<Array<FunctionArgAndPositions>>, metadata: laxe.parsers.Parser.Metadata, pos: Position) {
		super(p, name, arguments, metadata);

		this.expr = expr;
		this.retType = retType;
		this.pos = pos;

		checkIsExtension();
		checkIsScopable();
		checkRestArguments();
		verifyReturnType(retType);
		makeCallable();
	}

	override function metaType() {
		return "macro";
	}

	function checkIfSpecialArgument(arg: FunctionArgAndPositions, name: String): Bool {
		return if(arg.arg.name == name) {
			final t = arg.arg.type;
			switch(t) {
				case TPath({ pack: ["laxe", "stdlib"], name: "LaxeExpr" }): {
					true;
				}
				case _: {
					var pos = arg.typePos;
					if(pos == null) pos = arg.identPos;
					error('\'$name\' argument must be of type expr`', pos);
					false;
				}
			}
		} else {
			false;
		}
	}

	function checkIsExtension() {
		if(hasArguments) {
			isExtension = checkIfSpecialArgument(arguments[0], "self");
		}
	}

	function checkIsScopable() {
		if(hasArguments) {
			isScopable = checkIfSpecialArgument(arguments[arguments.length - 1], "scope");
		}
	}

	// Rest-arguments are allowed to be second-to-last in macro functions
	// if the last argument is the "scope" argument.
	// Therefore, the check to ensure rest arguments are last is disabled
	// during the parsing of macros, so it must be checked now.
	function checkRestArguments() {
		if(hasArguments) {
			final validIndex = arguments.length - (isScopable ? 2 : 1);
			var index = 0;
			for(a in arguments) {
				switch(a.arg.type) {
					case TPath({ pack: ["haxe"], name: "Rest" }): {
						if(index != validIndex) {
							error("Rest argument must be last argument for function", p.mergePos(a.identPos, a.typePos));
						}
					}
					case _:
				}
				index++;
			}
		}
	}

	function verifyReturnType(t: ComplexType): Bool {
		final result = switch(t) {
			case TPath({ name: "String", pack: [], sub: null }) |
				TPath({ pack: ["laxe", "stdlib"], name: "LaxeString", sub: null }): {
				isStringReturn = true;
				true;
			}
			case TPath({ pack: ["haxe", "macro"], name: "Expr", sub: null }) |
				TPath({ pack: ["laxe", "stdlib"], name: "LaxeExpr", sub: null }): {
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

	function convertRestToArr(f: FunctionArg) {
		return switch(f.type) {
			case TPath({ pack: ["haxe"], name: "Rest", params: p }): {
				{
					meta: f.meta,
					name: f.name,
					type: TPath({ pack: [], name: "Array", params: p }),
					opt: f.opt,
					value: f.value
				}
			}
			case _: f;
		}
	}

	function makeCallable() {
		final fun: Function = {
			args: hasArguments ? arguments.map(argAndPos -> convertRestToArr(argAndPos.arg)) : [],
			ret: retType,
			expr: expr
		};

		final funcExpr = {
			expr: EFunction(FNamed(name, false), fun),
			pos: pos
		};

		func = Eval.exprToFunction(funcExpr);
	}

	public function call(mPointer: MacroPointer, callee: Null<Expr>, scope: Null<Expr>): Null<Expr> {
		return if(func == null) {
			null;
		} else {
			final result: Null<Dynamic> = if(hasArguments) {
				var argInput: Null<Array<Expr>> = mPointer.params;
				if(callee != null) {
					argInput = [callee].concat(argInput);
				}

				final args = convertArguments(argInput, mPointer.pos, arguments.length - (isScopable ? 1 : 0));

				// Scope argument must be added after processing with convertArguments
				// so it can be added after any rest arguments.
				if(scope != null) {
					args.push((scope : Dynamic));
				}

				Reflect.callMethod(null, func, args);
			} else {
				func();
			}
			convertDynToExpr(result);
		}
	}

	function convertDynToExpr(d: Dynamic): Expr {
		return if(Std.isOfType(d, Array)) {
			var pos = null;
			if(pos == null) {
				pos = MacroManager.ProcessingPosition;
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
			laxe.stdlib.LaxeExpr.fromString(d, MacroManager.ProcessingPosition);
		} else {
			d;
		}
	}
}

#end
