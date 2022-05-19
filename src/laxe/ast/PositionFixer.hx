package laxe.ast;

#if (macro || laxeRuntime)

import haxe.macro.Expr;
import haxe.macro.Context;

class PositionFixer {
    public static inline function fix(p: Dynamic): Position {
        if(Type.getClassName(Type.getClass(p)) == null) {
			return Context.makePosition(cast p);
		}
        return p;
    }

    public static inline function expr(e: Dynamic): Expr {
		e.pos = fix(e.pos);
		return haxe.macro.ExprTools.map(e, expr);
	}

    public static inline function field(f: LaxeField) {
        f.pos = fix(f.pos);
        expr(f.getExpr());
    }

    public static inline function typeDef(f: LaxeTypeDefinition) {
        f.pos = fix(f.pos);
        for(f in f.fields) {
            field(f);
        }
    }
}

#end
