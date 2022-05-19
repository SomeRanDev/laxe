package laxe.ast;

import haxe.macro.Context;
import haxe.macro.Expr.ComplexType;
import haxe.macro.Expr.TypeDefinition;

@:nullSafety(Strict)
@:forward
abstract LaxeTypeDefinition(TypeDefinition) from TypeDefinition to TypeDefinition {
	public inline function new(t: TypeDefinition) {
		this = t;
	}

	public function getAllExpr(): Array<LaxeExpr> {
		final result: Array<LaxeExpr> = [];
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

	public inline function addVar(name: String, expr: Null<LaxeExpr> = null, type: Null<ComplexType> = null) {
		this.fields.push({
			name: name,
			pos: expr != null ? expr.pos : this.pos,
			kind: FVar(type, expr),
			access: [APublic]
		});
	}
}
