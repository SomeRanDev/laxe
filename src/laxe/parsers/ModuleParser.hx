package laxe.parsers;

#if macro

import sys.io.File;

import haxe.io.Path;

import haxe.macro.Context;
import haxe.macro.Expr.TypePath;
import haxe.macro.Expr.ImportExpr;
import haxe.macro.Expr.TypeDefinition;

class ModuleParser {
	var modulePath: String;
	var types: Array<TypeDefinition>;
	var imports: Null<Array<ImportExpr>>;
	var usings: Null<Array<TypePath>>;

	public function new(filePath: String, path: Path) {
		modulePath = generateModulePath(path);
		types = [];
		imports = null;
		usings = null;

		final content = File.getContent(filePath);

		Context.fatalError("Testing errors", Context.makePosition({
			min: 0,
			max: 10,
			file: "Test.lx"
		}));

		types.push({
			pos: Context.currentPos(),
			pack: ["a"],
			name: "main",
			kind: TDField(FFun({
				args: [],
				expr: {
					pos: Context.currentPos(),
					expr: ECall({
						pos: Context.currentPos(),
						expr: EConst(CIdent("trace"))
					}, [{
						pos: Context.currentPos(),
						expr: EConst(CString("wwwwww"))
					}])
				}
			}), []),
			fields: []
		});
	}

	function generateModulePath(p: Path) {
		return if(p.file.length > 0) {
			var result = p.dir == null ? p.file : Path.normalize(Path.join([p.dir, p.file]));
			result = StringTools.replace(result, "/", ".");
			result = StringTools.replace(result, "\\", ".");
			result;
		} else {
			"";
		}
	}

	public function defineModule() {
		Context.defineModule(modulePath, types, imports, usings);
	}
}

#end
