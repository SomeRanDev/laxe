package laxe.ast;

#if (macro || laxeRuntime)

import laxe.parsers.ModuleParser;

import haxe.macro.Expr;
import haxe.macro.Context;

class DecorPointer {
	public var path(default, null): TypePath;
	public var pos(default, null): Position;
	public var params(default, null): Null<Array<Expr>>;

	public var target(default, null): Null<Expr> = null;

	public function new(path: TypePath, pos: Position, params: Null<Array<Expr>>) {
		this.path = path;
		this.pos = pos;
		this.params = params;
	}

	public function setExpr(e: Expr) {
		target = e;
	}

	public function name() {
		return path.pack.join(".") + path.name + (path.sub != null ? path.sub : "");
	}
}

class DecorManager {
	final exprMap: Map<String, Array<DecorPointer>>;

	public static var ProcessingPosition: Null<Position>;

	public function new() {
		exprMap = [];
		ProcessingPosition = null;
	}

	public function addPointerToExpr(d: DecorPointer) {
		final pathStr = d.name();
		if(!exprMap.exists(pathStr)) {
			exprMap.set(pathStr, []);
		}
		exprMap[pathStr].push(d);
	}

	inline function pathToString(p: TypePath) {
		return haxe.macro.ComplexTypeTools.toString(TPath(p));
	}

	public function ApplyDecors(module: ModuleParser) {
		for(path => decorList in exprMap) {
			@:privateAccess {
				for(d in decorList) {
					ProcessingPosition = d.pos;
					final decor = module.findDecorFromTypePath(d.path);
					if(decor != null) {
						if(decor.onExpr != null) {
							if(d.target != null) {
								final result = decor.onExpr(d.target);
								if(result != null) {
									d.target.expr = result.expr;
									d.target.pos = result.pos;
								}
							}
						} else {
							Context.warning('Decorator ${pathToString(d.path)} does not define an onExpr(expr) -> expr method', d.pos);
						}
					} else {
						Context.warning('Decorator ${pathToString(d.path)} could not be found', d.pos);
					}
				}
			}
		}
	}
}

#end
