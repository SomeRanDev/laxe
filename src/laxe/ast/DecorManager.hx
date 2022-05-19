package laxe.ast;

#if (macro || laxeRuntime)

import laxe.ast.LaxeTypeDefinition;

import laxe.parsers.ModuleParser;

import haxe.macro.Expr;
import haxe.macro.Context;

class DecorPointer {
	public var path(default, null): TypePath;
	public var pos(default, null): Position;
	public var params(default, null): Null<Array<Expr>>;

	public var targetExpr(default, null): Null<Expr> = null;
	public var targetTypeDef(default, null): Null<TypeDefinition> = null;

	public function new(path: TypePath, pos: Position, params: Null<Array<Expr>>) {
		this.path = path;
		this.pos = pos;
		this.params = params;
	}

	public function setExpr(e: Expr) {
		targetExpr = e;
	}

	public function setTypeDef(t: TypeDefinition) {
		targetTypeDef = t;
	}

	public function name() {
		return path.pack.join(".") + path.name + (path.sub != null ? path.sub : "");
	}
}

class DecorManager {
	final pointerMap: Map<String, Array<DecorPointer>>;

	public static var ProcessingPosition: Null<Position>;

	public function new() {
		pointerMap = [];
		ProcessingPosition = null;
	}

	public function addPointer(d: DecorPointer) {
		final pathStr = d.name();
		if(!pointerMap.exists(pathStr)) {
			pointerMap.set(pathStr, []);
		}
		pointerMap[pathStr].push(d);
	}

	inline function pathToString(p: TypePath) {
		return haxe.macro.ComplexTypeTools.toString(TPath(p));
	}

	public function ApplyDecors(module: ModuleParser) {
		for(path => decorList in pointerMap) {
			for(d in decorList) {
				ProcessingPosition = d.pos;
				final decor = module.findDecorFromTypePath(d.path);
				if(decor != null) {
					if(d.targetExpr != null) {
						if(decor.onExpr != null) {
							final result = decor.onExpr({
								expr: d.targetExpr.expr,
								pos: d.targetExpr.pos
							});
							if(result != null) {
								PositionFixer.expr(result);
								d.targetExpr.expr = result.expr;
								d.targetExpr.pos = result.pos;
							}
						} else {
							Context.warning('Decorator \'${pathToString(d.path)}\' does not define an onExpr(expr) -> expr method', d.pos);
						}
					} else if(d.targetTypeDef != null) {
						if(decor.onTypeDef != null) {
							final result: LaxeTypeDefinition = decor.onTypeDef(Reflect.copy(d.targetTypeDef));
							if(result != null) {
								PositionFixer.typeDef(result);
								d.targetTypeDef.pack = result.pack;
								d.targetTypeDef.name = result.name;
								d.targetTypeDef.doc = result.doc;
								d.targetTypeDef.pos = result.pos;
								d.targetTypeDef.meta = result.meta;
								d.targetTypeDef.params = result.params;
								d.targetTypeDef.isExtern = result.isExtern;
								d.targetTypeDef.kind = result.kind;
								d.targetTypeDef.fields = result.fields;
							}
						} else {
							Context.warning('Decorator \'${pathToString(d.path)}\' does not define an onTypeDef(haxe.macro.TypeDefinition) -> haxe.macro.TypeDefinition method', d.pos);
						}
					}
				} else {
					Context.warning('Decorator \'${pathToString(d.path)}\' could not be found', d.pos);
				}
			}
		}
	}
}

#end
