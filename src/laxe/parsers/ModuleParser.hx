package laxe.parsers;

import laxe.types.Tuple;
#if (macro || laxeRuntime)

import sys.io.File;

import haxe.io.Path;

import haxe.macro.Context;
import haxe.macro.Expr.TypePath;
import haxe.macro.Expr.ImportExpr;
import haxe.macro.Expr.TypeDefinition;

@:nullSafety(Strict)
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

		final parser = new Parser(content, filePath);

		var lastIndex = null;

		while(!parser.ended) {
			parser.parseWhitespaceOrComments();

			if(lastIndex != parser.getIndex()) {
				lastIndex = parser.getIndex();
			} else {
				parser.errorHere("Unexpected content at module-level");
				break;
			}

			parseFunction(parser);
		}
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

	function parseFunction(p: Parser) {
		final startIndex = p.getIndex();
		final access = p.parseAllAccessWithPublic();
		final def = p.tryParseIdent("def");
		if(def != null) {
			final name = p.parseNextIdent();

			var args = p.parseNextFunctionArgs();
			if(args == null) args = [];

			final retType = if(p.findAndParseNextContent("->")) {
				p.parseNextType();
			} else {
				null;
			}

			final expr = if(p.findAndCheckAhead(":")) {
				p.parseBlock();
			} else if(p.findAndParseNextContent("=")) {
				p.parseWhitespaceOrComments();
				final result = p.parseNextExpression();
				p.findAndParseNextContent(";");
				result;
			} else {
				null;
			}

			types.push({
				pos: p.makePosition(startIndex),
				pack: [],
				name: name.ident,
				kind: TDField(FFun({
					args: args,
					ret: retType,
					expr: expr
				}), access),
				fields: []
			});
		}
	}
}

#end
