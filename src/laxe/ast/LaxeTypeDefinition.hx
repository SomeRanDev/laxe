package laxe.ast;

#if(macro || laxeRuntime)

import haxe.macro.Expr.TypeDefinition;

@:nullSafety(Strict)
@:forward
abstract LaxeTypeDefinition(TypeDefinition) from TypeDefinition to TypeDefinition {
    public inline function new(t: TypeDefinition) {
        this = t;
    }

    public inline function getAllExpr(): Array<LaxeExpr> {
        final result = [];
        if(this.fields != null && this.fields.length > 0) {
            for(f in this.fields) {
                final e = (f : LaxeField).getExpr();
                if(e != null) {
                    result.push(e);
                }
            }
        }
        return result;
    }
}

#end