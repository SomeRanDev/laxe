package laxe.parsers;

#if (macro || laxeRuntime)

import haxe.macro.Context;
import haxe.macro.Expr;

import laxe.parsers.ValueParser;

typedef StringAndPos = { ident: String, pos: Position };

@:nullSafety(Strict)
class ParserState {
	public var index(default, null): Int;
	public var lineNumber(default, null): Int;
	public var ended(default, null): Bool;

	public function new(parser: Parser) {
		index = parser.index;
		lineNumber = parser.lineNumber;
		ended = parser.ended;
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

	var lineIndent: String = "";
	var touchedContentOnThisLine: Bool = false;

	// constructor
	public function new(content: String, filePath: String) {
		this.content = content;
		this.filePath = filePath;
	}

	// access
	public function getIndex(): Int { return index; }
	public function getContent(): String { return content; }

	// save/restore state
	public function saveParserState(): ParserState {
		return new ParserState(this);
	}

	public function restoreParserState(state: ParserState) {
		index = state.index;
		lineNumber = state.lineNumber;
		ended = state.ended;
	}

	// position
	public function makePosition(start: Int) {
		return Context.makePosition({ min: start, max: index, file: filePath });
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

	public function parseNextContent(content: String): Bool {
		if(checkAhead(content)) {
			incrementIndex(content.length);
			return true;
		}
		return false;
	}

	// white-space/comments
	public function parseWhitespaceOrComments(untilNewline: Bool = false): Bool {
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
		return (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95;
	}

	function isIdentChar(c: Null<Int>): Bool {
		return isNumberChar(c) || isIdentCharStarter(c);
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

	// value
	public function parseNextValue(): Null<Expr> {
		final valueParser = new ValueParser(this);
		return valueParser.parseValueExpr();
	}
}

#end
