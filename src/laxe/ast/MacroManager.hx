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

	public var callee(default, null): Null<Expr>;
	public var isExtension(default, null): Bool;

	public var targetExpr(default, null): Null<Expr> = null;

	public function new(path: TypePath, pos: Position, params: Null<Array<Expr>>, callee: Null<Expr>, isExtension: Bool) {
		this.path = path;
		this.pos = pos;
		this.params = params;

		this.callee = callee;
		this.isExtension = isExtension;
	}

	public function setExpr(e: Expr) {
		targetExpr = e;
	}

	public function name() {
		return path.pack.join(".") + path.name + (path.sub != null ? path.sub : "");
	}

	public function possibleExtension() {
		return path.pack.length > 0 || path.sub != null;
	}

	public function pathLast(): TypePath {
		final name = if(path.sub != null) {
			path.sub;
		} else {
			path.name;
		}
		return { pack: [], name: name };
	}

	public function setIsExtension(v: Bool) {
		isExtension = v;
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
				var mac = module.findMacroFromTypePath(m.path);
				var isExtension = m.isExtension;

				// If the typepath cannot be found, it may be because it's actually
				// an extension macro call. So check if the final ident is a macro?
				if(mac == null && m.possibleExtension()) {
					mac = module.findMacroFromTypePath(m.pathLast());
					isExtension = true;
				}

				if(mac != null) {
					if(isExtension && !mac.isExtension) {
						Context.error('Macro \'${pathToString(m.path)}\' is being called as extension but does not have self argument.', m.pos);
					}

					if(m.targetExpr != null) {
						final result = mac.call(m, isExtension ? {
							expr: m.callee.expr,
							pos: m.callee.pos
						} : null);
						if(result != null) {
							PositionFixer.expr(result);
							m.targetExpr.expr = result.expr;
							m.targetExpr.pos = result.pos;
						} else {
							Context.error('Macro \'${pathToString(m.path)}\' did not generate a valid expression.', m.pos);
						}
					}
				} else {
					Context.error('Macro \'${pathToString(m.path)}\' could not be found', m.pos);
				}
			}
		}
	}
}

#end
