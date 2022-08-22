package laxe.ast;

#if (macro || laxeRuntime)

import haxe.macro.Expr;

function ResolveDefaultValue(t: ComplexType): Null<Expr> {
	return switch(t) {
		case TPath(p) if(p.sub == null && p.params == null && p.pack.length == 0): {
			switch(p.name) {
				case "int" | "Int" | "float" | "Float" | "Single" | "UInt": {
					macro 0;
				}
				case "bool" | "Bool": {
					macro false;
				}
				case "str" | "String": {
					macro "";
				}
				case _: {
					null;
				}
			}
		}
		case TPath({ pack: ["laxe", "stdlib" ], name: "LaxeString" }): {
			macro "";
		}
		case TParent(t) | TNamed(_, t): {
			ResolveDefaultValue(t);
		}
		case _: {
			null;
		}
	}
}

#end
