package laxe.ast.comptime;

#if (macro || laxeRuntime)

import laxe.parsers.Parser;

import haxe.macro.Expr;
import haxe.macro.Context;

typedef FunctionArgAndPositions = { arg: FunctionArg, identPos: Position, typePos: Null<Position> };

@:nullSafety(Strict)
class CompTimeFunc {
	public var name(default, null): String;

	var p: Parser;
	var arguments: Null<Array<FunctionArgAndPositions>>;
	var metadata: laxe.parsers.Parser.Metadata;

	var hasArguments: Bool;

	public function new(p: Parser, name: String, arguments: Null<Array<FunctionArgAndPositions>>, metadata: laxe.parsers.Parser.Metadata) {
		this.p = p;
		this.name = name;
		this.arguments = arguments;
		this.metadata = metadata;

		hasArguments = arguments != null && arguments.length > 0;

		verifyArguments();
	}

	function metaType() {
		return "macro";
	}

	function error(msg: String, pos: Position) {
		Context.error(msg, pos);
	}

	function verifyArguments() {
		if(arguments == null) return;
		for(a in arguments) {
			final t = a.arg.type;
			if(t != null) {
				if(!isValidDecorArgument(t)) {
					error(verifyArgumentsErrorMsg(t), a.typePos);
				}
			}
		}
	}

	function verifyArgumentsErrorMsg(t: ComplexType) {
		final tstr = haxe.macro.ComplexTypeTools.toString(t);
		return '$tstr is not a valid ${metaType()} argument type. Only int, float, bool, str, dyn, expr`, T?, T[], ...T, or anonymous structs may be used.';
	}

	function isRest(t: ComplexType): Null<ComplexType> {
		return switch(t) {
			case TPath({ pack: ["haxe"], name: "Rest", sub: null, params: [TPType(t2)] }): t2;
			case _: null;
		}
	}

	function convertArguments(inputArgs: Null<Array<Expr>>, errorPos: Position): Array<Dynamic> {
		final result: Array<Dynamic> = [];
		var index = 0;
		for(a in arguments) {
			final isRestType = isRest(a.arg.type);
			if(isRestType != null) {
				if(inputArgs != null) {
					final restInputs = [];
					while(inputArgs.length > index) {
						restInputs.push(convertArgumentInput(isRestType, inputArgs[index]));
						index++;
					}
					result.push(restInputs);
					continue;
				}
			}
			result.push(if(inputArgs != null && inputArgs.length > index) {
				if(a.arg.type != null) {
					convertArgumentInput(a.arg.type, inputArgs[index]);
				} else {
					inputArgs[index];
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
				throw error(metaType() + " missing argument (#" + (index + 1) + ") " + a.arg.name + ": " + typeName, errorPos);
			});
			index++;
		}
		return result;
	}

	function isValidDecorArgument(t: ComplexType): Bool {
		return switch(t) {
			case TAnonymous(_): true;
			case TParent(t2): isValidDecorArgument(t2);
			case TOptional(t2): isValidDecorArgument(t2);
			case TNamed(_, t2): isValidDecorArgument(t2);
			case TPath({ pack: ["laxe", "ast"], name: "LaxeExpr" }): true;
			case TPath({ pack: ["haxe", "macro"], name: "Expr" }): true;
			case TPath({ pack: ["haxe"], name: "Rest", params: p }) if(p != null && p.length == 1): {
				switch(p[0]) {
					case TPType(paramType): {
						isValidDecorArgument(paramType);
					}
					case _: false;
				}
			}
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
					case _: throw error("int expected", input.pos);
				}
			}
			case "float": {
				switch(input.expr) {
					case EConst(CInt(v)): Std.parseFloat(v);
					case EConst(CFloat(v)): Std.parseFloat(v);
					case EConst(CIdent("null")) if(isNullable): null; 
					case _: throw error("float expected", input.pos);
				}
			}
			case "bool": {
				switch(input.expr) {
					case EConst(CIdent("true")): true;
					case EConst(CIdent("false")): false;
					case EConst(CIdent("null")) if(isNullable): null; 
					case _: throw error("bool expected", input.pos);
				}
			}
			case "str": {
				switch(input.expr) {
					case EConst(CString(s, kind)): s;
					case _: throw error("str expected", input.pos);
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
							throw error("unknown array desired", input.pos);
						} else {
							values.map(v -> convertArgumentInput(paramType, v));
						}
					}
					case _: throw error("array expected", input.pos);
				}
			}
			case "expr": input;
			case _: input;
		}
	}
}

#end
