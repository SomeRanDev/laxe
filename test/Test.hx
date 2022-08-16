import haxe.macro.Context;
import haxe.macro.Compiler;

#if !macro
@:autoBuild(LaxeTestMacro.build())
#end
class LaxeTest {
	public function test(): Void {
		throw "test() function should be overriden in child class.";
	}

	public function assert(cond: Bool, ?pos: haxe.PosInfos) {
		if(!cond) {
			haxe.Log.trace(pos.className + " assert failed!", pos);
		}
	}
}

class Test {
	public static var laxeTest: Array<String>;
}

function main() {
	final tests: Array<String> = getLaxeTests();
	for(c in tests) {
		final cls = Type.resolveClass(c);
		final test = Type.createInstance(cls, []);
		try {
			Reflect.callMethod(test, Reflect.getProperty(test, "test"), []);
		} catch(e) {
			trace(e);
		}
	}
	trace("All tests complete!");
}

macro function getLaxeTests() {
	return macro $v{Test.laxeTest};
}

class LaxeTestMacro {
	public static function build() {
		#if macro
		if(Test.laxeTest == null) {
			Test.laxeTest = [];
		}
		final cls = Context.getLocalClass().get();
		final pack = cls.pack.copy();
		pack.push(cls.name);
		Test.laxeTest.push(pack.join("."));
		#end
		return null;
	}
}

