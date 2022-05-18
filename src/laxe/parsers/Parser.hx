package laxe.parsers;

#if (macro || laxeRuntime)

import haxe.ds.Either;

import haxe.macro.Context;
import haxe.macro.Expr;

import laxe.parsers.ValueParser;
import laxe.parsers.ModuleParser;
import laxe.ast.DecorManager.DecorPointer;

typedef StringAndPos = { ident: String, pos: Position };

enum LaxeMeta {
	StringMeta(m: MetadataEntry);
	TypedMeta(d: DecorPointer);
}

typedef Metadata = { string: Array<MetadataEntry>, typed: Array<DecorPointer> };

@:nullSafety(Strict)
class ParserState {
	public var index(default, null): Int;
	public var lineNumber(default, null): Int;
	public var ended(default, null): Bool;

	var lineStartIndex: Int;
	var lineIndent: String;
	var lastParsedWhitespaceIndex: Int;
	var touchedContentOnThisLine: Bool;

	var isTemplate: Bool;

	public function new(parser: Parser) {
		index = parser.index;
		lineNumber = parser.lineNumber;
		ended = parser.ended;

		@:privateAccess {
			lineStartIndex = parser.lineStartIndex;
			lineIndent = parser.lineIndent;
			lastParsedWhitespaceIndex = parser.lastParsedWhitespaceIndex;
			touchedContentOnThisLine = parser.touchedContentOnThisLine;
			isTemplate = parser.isTemplate;
		}
	}
}

@:nullSafety(Strict)
class Parser {
	// fields
	public var index(default, null): Int = 0;
	public var content(default, null): String = "";
	public var filePath(default, null): String = "";

	public var ended(default, null): Bool = false;
	public var lineNumber(default, null): Int = 0;

	var module: ModuleParser;

	var lineStartIndex: Int = 0;
	var lineIndent: String = "";
	var lastParsedWhitespaceIndex: Int = -1;
	var touchedContentOnThisLine: Bool = false;

	var isTemplate: Bool;

	var forcedPos: Null<Position> = null;

	// constructor
	public function new(content: String, filePath: String, module: Null<ModuleParser> = null) {
		this.content = content;
		this.filePath = filePath;
		this.module = module;
	}

	public static function fromStaticPosition(content: String, pos: Position) {
		final result = new Parser(content, "");
		result.forcedPos = pos;
		return result;
	}

	// access
	public function getIndex(): Int { return index; }
	public function getContent(): String { return content; }
	public function getIndent(): String { return lineIndent; }

	// decor
	public function addExprDecorPointer(d: DecorPointer) {
		if(module != null) {
			module.addExprDecorPointer(d);
		}
	}

	public function startTemplate() {
		isTemplate = true;
	}

	public function endTemplate() {
		isTemplate = false;
	}

	// save/restore state
	public function saveParserState(): ParserState {
		return new ParserState(this);
	}

	public function restoreParserState(state: ParserState) {
		index = state.index;
		lineNumber = state.lineNumber;
		ended = state.ended;

		@:privateAccess {
			lineStartIndex = state.lineStartIndex;
			lineIndent = state.lineIndent;
			lastParsedWhitespaceIndex = state.lastParsedWhitespaceIndex;
			touchedContentOnThisLine = state.touchedContentOnThisLine;
			isTemplate = state.isTemplate;
		}
	}

	// position
	public function noPosition() {
		return Context.makePosition({
			min: 0,
			max: 0,
			file: ""
		});
	}

	public function herePosition() {
		if(forcedPos != null) return forcedPos;
		return makePosition(getIndex());
	}

	public function makePosition(start: Int) {
		if(forcedPos != null) return forcedPos;
		return Context.makePosition({ min: start, max: index, file: filePath });
	}

	public function makePositionExact(start: Int, end: Int) {
		if(forcedPos != null) return forcedPos;
		return Context.makePosition({ min: start, max: end, file: filePath });
	}

	public function mergePos(position1: Position, position2: Position): Position {
		final p1 = Context.getPosInfos(position1);
		final p2 = Context.getPosInfos(position2);
		if(p1.file == p2.file) {
			return Context.makePosition({
				min: p1.min < p2.min ? p1.min : p2.min,
				max: p1.max > p2.max ? p1.max : p2.max,
				file: p1.file
			});
		}
		error("Positions from different files cannot be merged.", position1);
		return position1;
	}

	public function nullExpr(): Expr {
		return { expr: EConst(CIdent("null")), pos: noPosition() };
	}

	// error report
	public function error(msg: String, pos: Position) {
		Context.fatalError(msg, pos);
	}

	public function errorHere(msg: String) {
		error(msg, herePosition());
	}

	public function warn(msg: String, pos: Position) {
		Context.warning(msg, pos);
	}

	// simple parsing access
	public function charAt(index: Int): Null<String> {
		return content.charAt(index);
	}

	public function currentChar(): Null<String> {
		return charAt(index);
	}

	public function charCodeAt(index: Int): Null<Int> {
		return content.charCodeAt(index);
	}

	public function currentCharCode(): Null<Int> {
		return charCodeAt(index);
	}

	public function charCodeIsNewLine(code: Null<Int>): Bool {
		return code == 10;
	}

	// basic parser functions
	public function incrementIndex(amount: Int, incrementedSpace: Bool = false): Bool {
		index += amount;
		if(!incrementedSpace) {
			touchedContentOnThisLine = true;
		}
		if(index >= content.length) {
			ended = true;
			return true;
		}
		return false;
	}

	public function checkAhead(check: String): Bool {
		final end = index + check.length;
		if(end > content.length) return false;
		for(i in index...end) {
			if(content.charAt(i) != check.charAt(i - index)) {
				return false;
			}
		}
		return true;
	}

	public function findAndCheckAhead(check: String): Bool {
		parseWhitespaceOrComments();
		return checkAhead(check);
	}

	public function parseNextContent(content: String): Bool {
		if(checkAhead(content)) {
			incrementIndex(content.length);
			return true;
		}
		return false;
	}

	public function findAndParseNextContent(content: String): Bool {
		parseWhitespaceOrComments();
		return parseNextContent(content);
	}

	// white-space/comments
	public function parseWhitespaceOrComments(untilNewline: Bool = false): Bool {
		if(lastParsedWhitespaceIndex == index) {
			return false;
		}
		final start = index;
		while(index < content.length) {
			final preParseIndex = index;
			parseWhitespace(untilNewline);
			if(checkAhead("\\\r\n")) {
				incrementIndex(2);
			}
			parseMultilineComment();
			parseComment();
			if(preParseIndex == index) {
				break;
			}
		}
		lastParsedWhitespaceIndex = index;
		return start != index;
	}

	function parseWhitespace(untilNewline: Bool = false): Bool {
		final start = index;
		var hitNewLine = false;
		while(StringTools.isSpace(content, index)) {
			if(charCodeIsNewLine(charCodeAt(index))) {
				if(untilNewline) {
					return true;
				}
				touchedContentOnThisLine = false;
				lineIndent = "";
				hitNewLine = true;
				incrementLine();
			} else if(hitNewLine) {
				lineIndent += currentChar();
			}
			if(incrementIndex(1)) {
				break;
			}
		}
		return start != index;
	}

	function parseComment(): Bool {
		if(checkAhead("#")) {
			var foundNewline = false;
			while(index < content.length) {
				if(charCodeIsNewLine(charCodeAt(index))) {
					incrementLine();
					foundNewline = true;
				}
				if(incrementIndex(1)) {
					break;
				}
				if(foundNewline) {
					return true;
				}
			}
		}
		return false;
	}

	// If "true", that means multiline ended on same line.
	function parseMultilineComment(): Bool {
		final start = "###";
		final end = "###";
		if(start.length == 0 || end.length == 0) return true;
		var result = true;
		var finished = false;
		if(parseNextContent(start)) {
			final endChar0 = end.charAt(0);
			while(index < content.length) {
				final char = charAt(index);
				if(char == endChar0) {
					if(parseNextContent(end)) {
						finished = true;
						break;
					}
				} else if(char == "\n") {
					result = false;
					incrementLine();
				}
				if(incrementIndex(1)) {
					break;
				}
			}
		}
		return result;
	}

	function incrementLine() {
		lineNumber++;
		lineStartIndex = getIndex() + 1;
	}

	// identifier parsing
	public function isNumberChar(c: Null<Int>): Bool {
		return c != null && (c >= 48 && c <= 57);
	}

	public function isDecimalNumberChar(c: Null<Int>): Bool {
		return isNumberChar(c) || c == 95;
	}

	function isIdentCharStarter(c: Null<Int>): Bool {
		if(c == null) return false;
		// letters, underscore (95), and dollar sign (36)
		return (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c == 36;
	}

	function isIdentChar(c: Null<Int>): Bool {
		return isNumberChar(c) || isIdentCharStarter(c);
	}

	public function parseNextIdentMaybeNumberStart(): Null<StringAndPos> {
		parseWhitespaceOrComments();
		final startIndex = getIndex();
		var result = null;
		if(isIdentChar(currentCharCode())) {
			result = "";
			while(isIdentChar(currentCharCode())) {
				result += currentChar();
				if(incrementIndex(1)) {
					break;
				}
			}
		}
		return result == null ? null : { ident: result, pos: makePosition(startIndex) };
	}

	public function parseNextIdentMaybeNumberStartOrElse(): StringAndPos {
		final result = parseNextIdentMaybeNumberStart();
		if(result == null) {
			error("Expected identifier", makePosition(getIndex()));
			return { ident: "", pos: noPosition() };
		}
		return result;
	}

	public function parseNextIdent(): Null<StringAndPos> {
		parseWhitespaceOrComments();
		final startIndex = getIndex();
		var result = null;
		if(isIdentCharStarter(currentCharCode())) {
			result = "";
			while(isIdentChar(currentCharCode())) {
				result += currentChar();
				if(incrementIndex(1)) {
					break;
				}
			}
		}
		return result == null ? null : { ident: result, pos: makePosition(startIndex) };
	}

	public function parseNextIdentOrElse(): StringAndPos {
		final result = parseNextIdent();
		if(result == null) {
			error("Expected identifier", makePosition(getIndex()));
			return { ident: "", pos: noPosition() };
		}
		return result;
	}

	public function tryParseIdent(ident: String): Null<StringAndPos> {
		final state = saveParserState();
		final identAndPos = parseNextIdent();
		if(identAndPos != null && identAndPos.ident == ident) {
			return identAndPos;
		}
		restoreParserState(state);
		return null;
	}

	public function tryParseOneIdent(...idents: String): Null<StringAndPos> {
		for(ident in idents) {
			final result = tryParseIdent(ident);
			if(result != null) {
				return result;
			}
		}
		return null;
	}

	public function tryParseMultiIdent(...idents: String): Array<StringAndPos> {
		final result = [];
		for(ident in idents) {
			final ident = tryParseIdent(ident);
			if(ident != null) {
				result.push(ident);
			}
		}
		return result;
	}

	public function tryParseMultiIdentOneEach(...idents: String): Array<StringAndPos> {
		final result = [];
		for(ident in idents) {
			final ident = tryParseIdent(ident);
			if(ident != null) {
				if(result.contains(ident)) {
					error("Unexpected identifier", ident.pos);
				} else {
					result.push(ident);
				}
			}
		}
		return result;
	}

	// value
	public function parseNextValue(): Null<Expr> {
		final valueParser = new ValueParser(this);
		return valueParser.parseValueExpr();
	}

	// type
	// TODO: support anonymous types and anonymous extends and intersection types
	public function parseNextType(): Null<ComplexType> {
		return TypeParser.parseType(this);
	}

	public function parseNextTypePath(): Null<TypePath> {
		parseWhitespaceOrComments();
		final startIndex = getIndex();
		final result = parseNextType();
		if(result == null) {
			return null;
		}
		return switch(result) {
			case TPath(path): return path;
			case _: {
				error("Invalid type parsed", makePosition(startIndex));
				null;
			}
		}
	}

	// basic expr
	public function parseNextExpression(): Null<Expr> {
		return ExpressionParser.expr(this);
	}

	public function parseNextExpressionList(endChar: String): Array<Expr> {
		final exprs = [];
		while(!ended) {
			if(findAndCheckAhead(endChar)) {
				incrementIndex(endChar.length);
				break;
			} else {
				exprs.push(parseNextExpression());
				if(findAndParseNextContent(",")) {
					continue;
				} else if(findAndParseNextContent(endChar)) {
					break;
				} else {
					error("Unexpected content", herePosition());
				}
			}
		}

		return exprs;
	}

	public function parseBlock(): Expr {
		final exprs = [];

		final startIndex = getIndex();

		if(parseNextContent(":")) {
			final parentLineIdent = lineIndent;
			var lastLineNumber = lineNumber;
			parseWhitespaceOrComments();

			var blockIdent: Null<String> = null;

			if(lastLineNumber != lineNumber) {
				if(lineIndent.length > parentLineIdent.length && StringTools.startsWith(lineIndent, parentLineIdent)) {
					blockIdent = lineIndent;
				} else {
					errorHere("Inconsistent indentation");
				}
			} else {
				final expr = parseNextExpression();
				findAndParseNextContent(";");
				return expr;
			}

			var endIndex = startIndex;
			if(blockIdent != null) {
				while(!ended) {
					if(lastLineNumber != lineNumber) {
						lastLineNumber = lineNumber;
						if(lineIndent == blockIdent) {
							exprs.push(parseNextExpression());
							endIndex = getIndex();
							parseWhitespaceOrComments();
						} else if(!StringTools.startsWith(blockIdent, lineIndent)) {
							error("Inconsistent ident", makePosition(lineStartIndex));
						} else {
							break;
						}
					} else if(parseNextContent(";")) {
						parseWhitespaceOrComments();
						if(lastLineNumber == lineNumber && !ended) {
							exprs.push(parseNextExpression());
							endIndex = getIndex();
							parseWhitespaceOrComments();
						}
					} else {
						break;
					}
				}
			}

			return {
				expr: EBlock(exprs),
				pos: makePositionExact(startIndex, endIndex)
			};
		}

		error("Expected :", herePosition());
		return nullExpr();
	}

	// function params
	public function parseNextFunctionArgs(): Null<Array<FunctionArg>> {
		if(findAndParseNextContent("(")) {
			final params: Array<FunctionArg> = [];

			if(!findAndParseNextContent(")")) {
				while(!ended) {
					final ident = parseNextIdent();
					if(ident == null) {
						errorHere("Expected identifier");
						break;
					}

					final type = if(findAndParseNextContent(":")) {
						parseNextType();
					} else {
						null;
					}
					
					final expr = if(findAndParseNextContent("=")) {
						parseNextExpression();
					} else {
						null;
					}

					// TODO: Meta
					
					params.push({
						name: ident.ident,
						type: type,
						value: expr
					});
					
					if(findAndParseNextContent(")")) {
						break;
					} else if(findAndParseNextContent(",")) {
						continue;
					} else {
						errorHere("Expected ')' or ','");
						break;
					}
				}
			}
			
			return params;
		}
		return null;
	}

	// metadata and decorators
	public function parseNextDecor(): Null<LaxeMeta> {
		final startIndex = getIndex();

		var name = null;
		var typePath = null;

		if(findAndParseNextContent("@")) {
			if(findAndParseNextContent("[")) {
				name = "";
				while(!ended && !checkAhead("]")) {
					name += currentChar();
					incrementIndex(1);
					if(checkAhead("]]")) {
						name += "]";
					}
				}
				incrementIndex(1);
			} else {
				typePath = parseNextTypePath();
				if(typePath == null) {
					errorHere("Expected type path");
					return null;
				}
			}
		} else {
			return null;
		}

		final exprs = if(parseNextContent("(")) {
			parseNextExpressionList(")");
		} else {
			null;
		}

		final pos = makePosition(startIndex);

		if(name != null) {
			return StringMeta({
				name: name,
				pos: pos,
				params: exprs
			});
		}

		return TypedMeta(new DecorPointer(typePath, pos, exprs));
	}

	public function parseAllNextDecors(): Metadata {
		var result = {
			string: null,
			typed: null
		};

		var meta = null;
		while((meta = parseNextDecor()) != null) {
			switch(meta) {
				case StringMeta(entry): {
					if(result.string == null) result.string = [];
					result.string.push(entry);
				}
				case TypedMeta(decor): {
					if(result.typed == null) result.typed = [];
					result.typed.push(decor);
				}
			}
		}

		return result;
	}

	// import
	public function parseAllNextImports(): Array<Either<ImportExpr, TypePath>> {
		final result = [];
		while(true) {
			{
				final imp = parseNextImport();
				if(imp != null) {
					result.push(Left(imp));
					continue;
				}
			}

			{
				final use = parseNextUsing();
				if(use != null) {
					result.push(Right(use));
					continue;
				}
			}

			break;
		}
		return result;
	}

	public function parseNextImport(): Null<ImportExpr> {
		if(findAndParseNextContent("import")) {
			parseWhitespaceOrComments();
			
			final paths = [];
			while(!ended) {
				var str = parseNextIdent();
				if(str != null) {
					paths.push({ name: str.ident, pos: str.pos });
					if(parseNextContent(".")) {
						continue;
					} else {
						parseNextContent(";");
						break;
					}
				} else {
					break;
				}
			}

			return {
				path: paths,
				mode: INormal
			};
		}
		return null;
	}

	public function parseNextUsing(): Null<TypePath> {
		if(findAndParseNextContent("using")) {
			final p = parseNextTypePath();
			if(p != null) {
				parseNextContent(";");
				return p;
			} else {
				errorHere("Expected type path");
			}
		}
		return null;
	}

	// props
	public function parseAllAccess(): Array<Access> {
		final accessorNames = tryParseMultiIdentOneEach("pub", "priv", "static", "override", "dyn",
			"inline", "macro", "final", "extern", "abstract", "overload");

		return accessorNames.map(a -> {
			return switch(a.ident) {
				case "pub": APublic;
				case "priv": APrivate;
				case "static": AStatic;
				case "override": AOverride;
				case "dyn": ADynamic;
				case "inline": AInline;
				case "macro": AMacro;
				case "final": AFinal;
				case "extern": AExtern;
				case "abstract": AAbstract;
				case "overload": AOverload;
				case _: null;
			}
		});
	}

	public function parseAllAccessWithPublic(): Array<Access> {
		final accessors = parseAllAccess();
		if(!accessors.contains(APrivate) && !accessors.contains(APublic)) {
			accessors.push(APublic);
		}
		return accessors;
	}

	// type params
	public function parseTypeParamDecls(): Null<Array<TypeParamDecl>> {
		if(findAndParseNextContent("<")) {
			final params: Array<TypeParamDecl> = [];
			
			while(true) {
				if(ended) {
					errorHere("Unexpected end of file");
					break;
				}

				// TODO meta

				final ident = parseNextIdent();
				final typeParams = parseTypeParamDecls();

				var constraints = null;
				if(findAndParseNextContent(":")) {
					constraints = [];
					final firstType = parseNextType();
					if(firstType == null) {
						errorHere("Expected type constraint");
						break;
					} else {
						constraints.push(firstType);
					}

					while(findAndParseNextContent("&")) {
						final type = parseNextType();
						if(type == null) {
							errorHere("Expected type constraint");
							break;
						} else {
							constraints.push(type);
						}
					}
				}

				params.push({
					name: ident.ident,
					params: typeParams,
					constraints: constraints
				});

				if(findAndParseNextContent(",")) {
					continue;
				} else if(findAndParseNextContent(">")) {
					break;
				} else {
					errorHere("Expected '>' or ','");
					break;
				}
			}

			return params;
		}
		return null;
	}
}

#end
