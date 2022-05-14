package laxe.ast;

#if (macro || laxeRuntime)

import haxe.macro.Expr;

class DecorPointer {
	var path: TypePath;
	var pos: Position;
	var params: Null<Array<Expr>>;

	var target: Expr;

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
	final Map: Map<String, Array<DecorPointer>>;

	public static var ProcessingPosition: Null<Position>;

	public function new() {
		Map = [];
		ProcessingPosition = null;
	}

	public function addPointer(d: DecorPointer) {
		final pathStr = d.name();
		if(!Map.exists(pathStr)) {
			Map.set(pathStr, []);
		}
		Map[pathStr].push(d);
	}

	public function ApplyDecors() {
		for(path => decorList in Map) {
			@:privateAccess {
				for(d in decorList) {
					ProcessingPosition = d.pos;
					final qq = macro 123;
					d.target.expr = qq.expr;
				}
			}
		}
	}
}

#end
