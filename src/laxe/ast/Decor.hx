package laxe.ast;

#if (macro || laxeRuntime)

import haxe.macro.Expr;

@:nullSafety(Strict)
class Decor {
	var p: laxe.parsers.Parser;
	var name: String;
	var fields: Array<Field>;
	var metadata: laxe.parsers.Parser.Metadata;

	static var validFunctionNames = ["onExpr"];

	var onExpr: Null<(Expr) -> Expr> = null;

	public function new(p: laxe.parsers.Parser, name: String, fields: Array<Field>, metadata: laxe.parsers.Parser.Metadata) {
		this.p = p;
		this.name = name;
		this.fields = fields;
		this.metadata = metadata;

		verifyFields();
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
		}
	}

	function setOnExpr(f: Field, fun: Function) {
		if(onExpr != null) {
			p.error("Duplicate onExpr function", f.pos);
			return;
		}

		if(fun.args.length == 1 && isComplexTypeExpr(fun.args[0].type) && isComplexTypeExprOrVoid(fun.ret)) {
			final funcExpr = {
				expr: EFunction(FNamed(f.name, false), fun),
				pos: f.pos
			};

			onExpr = Eval.exprToFunction(funcExpr);
		} else {
			p.error("onExpr function must match format (expr) -> expr? or (expr) -> void", f.pos);
		}
	}

	function isComplexTypeExpr(c: Null<ComplexType>) {
		return switch(c) {
			case TPath({ name: "ExprEx", pack: ["laxe", "ast"], sub: null, params: null }): {
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
}

#end
