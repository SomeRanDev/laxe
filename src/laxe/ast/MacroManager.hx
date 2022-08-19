package laxe.ast;

#if (macro || laxeRuntime)

import laxe.ast.LaxeTypeDefinition;

import laxe.parsers.ModuleParser;

import haxe.macro.Expr;
import haxe.macro.Context;

class MacroPointer {
	public var path(default, null): TypePath;
	public var pos(default, null): Position;
	public var params(default, null): Null<Array<Expr>>;

	public var targetExpr(default, null): Null<Expr> = null;

	public function new(path: TypePath, pos: Position, params: Null<Array<Expr>>) {
		this.path = path;
		this.pos = pos;
		this.params = params;
	}

	public function setExpr(e: Expr) {
		targetExpr = e;
	}

	public function name() {
		return path.pack.join(".") + path.name + (path.sub != null ? path.sub : "");
	}
}

class MacroManager {
	final pointerMap: Map<String, Array<MacroPointer>>;

	public static var ProcessingPosition: Null<Position>;

	public function new() {
		pointerMap = [];
		ProcessingPosition = null;
	}

	public function addPointer(m: MacroPointer) {
		final pathStr = m.name();
		if(!pointerMap.exists(pathStr)) {
			pointerMap.set(pathStr, []);
		}
		pointerMap[pathStr].push(m);
	}

	inline function pathToString(p: TypePath) {
		return haxe.macro.ComplexTypeTools.toString(TPath(p));
	}

	public function ApplyMacros(module: ModuleParser) {
		for(path => macroList in pointerMap) {
			for(m in macroList) {
				ProcessingPosition = m.pos;
				final mac = module.findMacroFromTypePath(m.path);
				if(mac != null) {
					if(m.targetExpr != null) {
						final result = mac.call(m);
						if(result != null) {
							PositionFixer.expr(result);
							m.targetExpr.expr = result.expr;
							m.targetExpr.pos = result.pos;
						} else {
							Context.error('Macro \'${pathToString(m.path)}\' did not generate a valid expression.', m.pos);
						}
					}
				} else {
					Context.warning('Macro \'${pathToString(m.path)}\' could not be found', m.pos);
				}
			}
		}
	}
}

#end
