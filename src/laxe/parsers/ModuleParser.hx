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
				parser.error("Unexpected content", parser.herePosition());
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
		final def = p.tryParseIdent("def");
		if(def != null) {
			p.parseWhitespaceOrComments();
			final name = p.parseNextIdent();
			p.parseWhitespaceOrComments();
			if(p.checkAhead("()")) {
				p.incrementIndex(2);
				p.parseWhitespaceOrComments();
				final expr = if(p.checkAhead(":")) {
					p.parseBlock();
				} else if(p.checkAhead("=")) {
					p.incrementIndex(1);
					p.parseWhitespaceOrComments();
					p.parseNextExpression();
				} else {
					null;
				}
				types.push({
					pos: p.makePosition(startIndex),
					pack: [],
					name: name.ident,
					kind: TDField(FFun({
						args: [],
						expr: expr
					}), []),
					fields: []
				});
			}
		}
	}
}

#end
