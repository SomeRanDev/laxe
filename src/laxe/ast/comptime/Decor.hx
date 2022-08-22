package laxe.ast.comptime;

#if (macro || laxeRuntime)

import laxe.ast.comptime.CompTimeFunc;

import laxe.ast.DecorManager.DecorPointer;

import haxe.macro.Expr;
import haxe.macro.Context;

@:nullSafety(Strict)
class Decor extends CompTimeFunc {
	var fields: Array<Field>;

	static var validFunctionNames = ["onExpr", "onTypeDef", "onField"];

	public var onExpr(default, null): Null<(Expr) -> Expr> = null;
	public var onTypeDef(default, null): Null<(TypeDefinition) -> TypeDefinition> = null;
	public var onField(default, null): Null<(Field) -> Field> = null;

	public function new(p: laxe.parsers.Parser, name: String, fields: Array<Field>, arguments: Null<Array<FunctionArgAndPositions>>, metadata: laxe.parsers.Parser.Metadata) {
		super(p, name, arguments, metadata);

		this.fields = fields;

		verifyFields();
	}

	override function metaType() {
		return "decor";
	}

	function verifyFields() {
		for(f in fields) {
			switch(f.kind) {
				case FFun(fun): {
					if(validFunctionNames.contains(f.name)) {
						addFunction(f, fun);
					} else {
						p.error("Invalid function name within decor " + f.name, f.pos);
					}
				}
				case _: {
					p.error("Only functions should be defined in decor", f.pos);
				}
			}
		}
	}

	function addFunction(f: Field, fun: Function) {
		switch(f.name) {
			case "onExpr": setOnExpr(f, fun);
			case "onTypeDef": setOnTypeDef(f, fun);
			case "onField": setOnField(f, fun);
		}
	}

	function convertPointerArguments(dPointer: DecorPointer): Array<Dynamic> {
		return convertArguments(dPointer.params, dPointer.pos);
	}

	public function hasOnExpr() {
		return onExpr != null;
	}

	public function callOnExpr(dPointer: DecorPointer, e: laxe.stdlib.LaxeExpr) {
		if(hasArguments) {
			final args = [(e : Dynamic)].concat(convertPointerArguments(dPointer));
			return Reflect.callMethod(null, onExpr, args);
		} else if(onExpr != null) {
			return onExpr(e);
		}
		return null;
	}

	function setOnExpr(f: Field, fun: Function) {
		if(onExpr != null) {
			p.error("Duplicate onExpr function", f.pos);
			return;
		}

		if(fun.args.length == 1 && isComplexTypeExpr(fun.args[0].type) && isComplexTypeExprOrVoid(fun.ret)) {
			if(hasArguments) {
				fun.args = fun.args.concat(arguments.map(argAndPos -> argAndPos.arg));
			}

			final funcExpr = {
				expr: EFunction(FNamed(f.name, false), fun),
				pos: f.pos
			};

			onExpr = Eval.exprToFunction(funcExpr);
		} else {
			p.error("onExpr function must match format (expr`) -> expr`? or (expr`) -> void", f.pos);
		}
	}

	public function hasOnTypeDef() {
		return onTypeDef != null;
	}

	public function callOnTypeDef(dPointer: DecorPointer, td: laxe.stdlib.LaxeTypeDefinition) {
		if(hasArguments) {
			final args = [(td : Dynamic)].concat(convertPointerArguments(dPointer));
			return Reflect.callMethod(null, onTypeDef, args);
		} else if(onTypeDef != null) {
			return onTypeDef(td);
		}
		return null;
	}

	function setOnTypeDef(f: Field, fun: Function) {
		if(onTypeDef != null) {
			p.error("Duplicate onTypeDef function", f.pos);
			return;
		}

		if(hasArguments) {
			fun.args = fun.args.concat(arguments.map(argAndPos -> argAndPos.arg));
		}

		final funcExpr = {
			expr: EFunction(FNamed(f.name, false), fun),
			pos: f.pos
		};

		onTypeDef = Eval.exprToFunction(funcExpr);
	}

	public function hasOnField() {
		return onField != null;
	}

	public function callOnField(dPointer: DecorPointer, f: laxe.stdlib.LaxeField) {
		if(hasArguments) {
			final args = [(f : Dynamic)].concat(convertPointerArguments(dPointer));
			return Reflect.callMethod(null, onField, args);
		} else if(onField != null) {
			return onField(f);
		}
		return null;
	}

	function setOnField(f: Field, fun: Function) {
		if(onField != null) {
			p.error("Duplicate onField function", f.pos);
			return;
		}

		if(hasArguments) {
			fun.args = fun.args.concat(arguments.map(argAndPos -> argAndPos.arg));
		}

		final funcExpr = {
			expr: EFunction(FNamed(f.name, false), fun),
			pos: f.pos
		};

		onField = Eval.exprToFunction(funcExpr);
	}

	function isComplexTypeExpr(c: Null<ComplexType>) {
		return switch(c) {
			case TPath({ name: "LaxeExpr", pack: ["laxe", "stdlib"], sub: null, params: null }): {
				true;
			}
			case _: false;
		}
	}

	function isComplexTypeTypeDef(c: Null<ComplexType>) {
		return switch(c) {
			case TPath({ name: "TypeDefinition", pack: ["haxe", "macro"], sub: null, params: null }): {
				true;
			}
			case _: false;
		}
	}

	function isComplexTypeExprOrVoid(c: Null<ComplexType>) {
		if(c == null) {
			return true;
		}
		return switch(c) {
			case TPath({ name: "Void", pack: [], sub: null, params: null }): {
				true;
			}
			case _: isComplexTypeExpr(c);
		}
	}

	function isComplexTypeTypeDefOrVoid(c: Null<ComplexType>) {
		if(c == null) {
			return true;
		}
		return switch(c) {
			case TPath({ name: "Void", pack: [], sub: null, params: null }): {
				true;
			}
			case _: isComplexTypeTypeDef(c);
		}
	}
}

#end
