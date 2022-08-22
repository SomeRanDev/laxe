package laxe.stdlib;

@:nullSafety(Strict)
@:forward
@:remove
abstract LaxeString(String) from String to String {
	@:op(A + B)
	public static inline function addStr(str: LaxeString, str2: LaxeString): LaxeString {
		return (str: String) + (str2: String);
	}

	@:op(A + B)
	public static inline function addInt(str: LaxeString, i: Int): LaxeString {
		return (str: String) + i;
	}

	@:op(A + B)
	public static inline function addInt2(i: Int, str: LaxeString): LaxeString {
		return i + (str: String);
	}

	public inline function contains(value: LaxeString): Bool {
		return StringTools.contains(this, value);
	}

	public function replace(sub: LaxeString, by: LaxeString): String {
		return StringTools.replace(this, sub, by);
	}

	public inline function startsWith(start: LaxeString): Bool {
		return StringTools.startsWith(this, start);
	}

	public inline function endsWith(end: LaxeString): Bool {
		return StringTools.endsWith(this, end);
	}

	public inline function isSpace(pos: Int): Bool {
		return StringTools.isSpace(this, pos);
	}

	public inline function trim(): String {
		return StringTools.trim(this);
	}

	public inline function ltrim(): String {
		return StringTools.ltrim(this);
	}

	public inline function rtrim(): String {
		return StringTools.rtrim(this);
	}

	public inline function lpad(c: LaxeString, l: Int): String {
		return StringTools.lpad(this, c, l);
	}

	public inline function rpad(c: LaxeString, l: Int): String {
		return StringTools.rpad(this, c, l);
	}

	public inline function fastCodeAt(index: Int): Int {
		return StringTools.fastCodeAt(this, index);
	}

	public inline function unsafeCodeAt(index: Int): Int {
		return StringTools.unsafeCodeAt(this, index);
	}

	public inline function htmlEscape(?quotes: Bool): String {
		return StringTools.htmlEscape(this, quotes);
	}

	public inline function htmlUnescape(): String {
		return StringTools.htmlUnescape(this);
	}

	public inline function urlDecode(): String {
		return StringTools.urlDecode(this);
	}

	public inline function urlEncode(): String {
		return StringTools.urlEncode(this);
	}
}
