package laxe.ast;

#if (macro || laxeRuntime)

import laxe.ast.DecorManager.DecorPointer;

import haxe.macro.Expr;
import haxe.macro.Context;

typedef FunctionArgAndPositions = { arg: FunctionArg, identPos: Position, typePos: Null<Position> };

@:nullSafety(Strict)
class Decor {
	var p: laxe.parsers.Parser;
	public var name(default, null): String;
	var fields: Array<Field>;
	var arguments: Null<Array<FunctionArgAndPositions>>;
	var metadata: laxe.parsers.Parser.Metadata;

	var hasArguments: Bool;

	static var validFunctionNames = ["onExpr", "onTypeDef", "onField"];

	public var onExpr(default, null): Null<(Expr) -> Expr> = null;
	public var onTypeDef(default, null): Null<(TypeDefinition) -> TypeDefinition> = null;
	public var onField(default, null): Null<(Field) -> Field> = null;

	public var onExprWArgs(default, null): Null<Dynamic> = null;

	public function new(p: laxe.parsers.Parser, name: String, fields: Array<Field>, arguments: Null<Array<FunctionArgAndPositions>>, metadata: laxe.parsers.Parser.Metadata) {
		this.p = p;
		this.name = name;
		this.fields = fields;
		this.arguments = arguments;
		this.metadata = metadata;

		hasArguments = arguments != null && arguments.length > 0;

		verifyFields();
		verifyArguments();
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

	function verifyArguments() {
		if(arguments == null) return;
		for(a in arguments) {
			final t = a.arg.type;
			if(t != null) {
				if(!isValidDecorArgument(t)) {
					final tstr = haxe.macro.ComplexTypeTools.toString(t);
					final errorMsg = tstr + " is not a valid decor argument type. Only int, float, bool, str, dyn, expr`, T?, T[], or anonymous structs may be used.";
					Context.error(errorMsg, a.typePos);
				}
			}
		}
	}

	function isValidDecorArgument(t: ComplexType) {
		return switch(t) {
			case TAnonymous(_): true;
			case TParent(t2): isValidDecorArgument(t2);
			case TOptional(t2): isValidDecorArgument(t2);
			case TNamed(_, t2): isValidDecorArgument(t2);
			case TPath({ pack: ["laxe", "ast"], name: "LaxeExpr" }): true;
			case TPath({ pack: ["haxe", "macro"], name: "Expr" }): true;
			case TPath(p): {
				if(p.pack.length == 0 && p.sub == null) {
					switch(p.name) {
						case "int" | "Int" |
							"float" | "Float" |
							"bool" | "Bool" |
							"str" | "String" |
							"dyn" | "Dynamic": true;

						case "Null" | "Array": {
							if(p.params != null && p.params.length == 1) {
								switch(p.params[0]) {
									case TPType(paramType): {
										isValidDecorArgument(paramType);
									}
									case _: false;
								}
							} else {
								false;
							}
						}

						case _: false;
					}
				} else {
					false;
				}
			}
			case _: false;
		}
	}

	function getDecorArgumentType(t: ComplexType): Null<String> {
		return switch(t) {
			case TAnonymous(_): "dyn";
			case TParent(t2): getDecorArgumentType(t2);
			case TOptional(t2): getDecorArgumentType(t2);
			case TNamed(_, t2): getDecorArgumentType(t2);
			case TPath({ pack: ["laxe", "ast"], name: "LaxeExpr" }): "expr";
			case TPath({ pack: ["haxe", "macro"], name: "Expr" }): "expr";
			case TPath(p): {
				if(p.pack.length == 0 && p.sub == null) {
					switch(p.name) {
						case "int" | "Int": "int";
						case "float" | "Float": "float";
						case "bool" | "Bool": "bool";
						case "str" | "String": "str";
						case "dyn" | "Dynamic": "dyn";
						case "Array": "array";
						case "Null": {
							if(p.params != null && p.params.length == 1) {
								switch(p.params[0]) {
									case TPType(paramType): {
										getDecorArgumentType(paramType);
									}
									case _: null;
								}
							} else {
								null;
							}
						}

						case _: null;
					}
				} else {
					null;
				}
			}
			case _: null;
		}
	}

	function convertArgumentInput(t: ComplexType, input: Expr): Dynamic {
		final isNullable = switch(t) {
			case TPath({ pack: [], sub: null, name: "Null" }): true;
			case _: false;
		}

		return switch(getDecorArgumentType(t)) {
			case "int": {
				switch(input.expr) {
					case EConst(CInt(v)): Std.parseInt(v);
					case EConst(CIdent("null")) if(isNullable): null; 
					case _: Context.error("int expected", input.pos);
				}
			}
			case "float": {
				switch(input.expr) {
					case EConst(CInt(v)): Std.parseFloat(v);
					case EConst(CFloat(v)): Std.parseFloat(v);
					case EConst(CIdent("null")) if(isNullable): null; 
					case _: Context.error("float expected", input.pos);
				}
			}
			case "bool": {
				switch(input.expr) {
					case EConst(CIdent("true")): true;
					case EConst(CIdent("false")): false;
					case EConst(CIdent("null")) if(isNullable): null; 
					case _: Context.error("bool expected", input.pos);
				}
			}
			case "str": {
				switch(input.expr) {
					case EConst(CString(s, kind)): s;
					case _: Context.error("str expected", input.pos);
				}
			}
			case "array": {
				switch(input.expr) {
					case EArrayDecl(values): {
						final paramType = switch(t) {
							case TPath(p): {
								if(p.params != null && p.params.length == 1) {
									switch(p.params[0]) {
										case TPType(t2): t2;
										case _: null;
									}
								} else {
									null;
								}
							}
							case _: null;
						}
						if(paramType == null) {
							Context.error("unknown array desired", input.pos);
						} else {
							values.map(v -> convertArgumentInput(paramType, v));
						}
					}
					case _: Context.error("array expected", input.pos);
				}
			}
			case "expr": input;
			case _: input;
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
		final result = [];
		var index = 0;
		for(a in arguments) {
			result.push(if(dPointer.params != null && dPointer.params.length > index) {
				if(a.arg.type != null) {
					convertArgumentInput(a.arg.type, dPointer.params[index]);
				} else {
					dPointer.params[index];
				}
			} else if(a.arg.value != null) {
				if(a.arg.type != null) {
					convertArgumentInput(a.arg.type, a.arg.value);
				} else {
					a.arg.value;
				}
			} else {
				final typeName = if(a.arg.type == null) {
					"expr`";
				} else {
					haxe.macro.ComplexTypeTools.toString(a.arg.type);
				}
				Context.error("Decor missing argument (#" + (index + 1) + ") " + a.arg.name + ": " + typeName, dPointer.pos);
			});
			index++;
		}
		return result;
	}

	public function hasOnExpr() {
		return onExpr != null;
	}

	public function callOnExpr(dPointer: DecorPointer, e: laxe.ast.LaxeExpr) {
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

	public function callOnTypeDef(dPointer: DecorPointer, td: laxe.ast.LaxeTypeDefinition) {
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

	public function callOnField(dPointer: DecorPointer, f: laxe.ast.LaxeField) {
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
			case TPath({ name: "LaxeExpr", pack: ["laxe", "ast"], sub: null, params: null }): {
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
