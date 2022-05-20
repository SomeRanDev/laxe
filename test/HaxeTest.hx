package;

function helloFromHaxe() {
	trace("Hello from Haxe!");
}

#if !macro

@:build(HaxeTest.Test())
enum Bla {
	One;
	Two(a: Int, b: Int);
	Three;
}

#else

function Test() {
	final f = haxe.macro.Context.getBuildFields();
	trace(f[1]);
	return null;
}

#end