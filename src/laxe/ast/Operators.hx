package laxe.ast;

#if (macro || laxeRuntime)

final PrefixOperators: Array<Operator> = [
	new Operator("positive", "-", 15),
	new Operator("negative", "+", 15),
	new Operator("logicNot", "!", 15),
	new Operator("bitNot", "~", 15),
	new Operator("preDecrement", "--", 15),
	new Operator("preIncrement", "++", 15)
];

final InfixOperators: Array<Operator> = [
	new Operator("dotAccess", ".", 16),

	new Operator("multiply", "*", 14),
	new Operator("divide", "/", 14),
	new Operator("modulus", "%", 14),

	new Operator("add", "+", 13),
	new Operator("subtract", "-", 13),

	new Operator("shiftLeft", "<<", 12),
	new Operator("shiftRight", ">>", 12),

	new Operator("spaceship", "<=>", 11),

	new Operator("lessThen", "<", 9),
	new Operator("lessThanOrEqual", "<=", 9),
	new Operator("greaterThan", ">", 9),
	new Operator("greaterThanOrEqual", ">=", 9),

	new Operator("equals", "==", 8),
	new Operator("notEquals", "!=", 8),

	new Operator("bitAnd", "&", 7),
	new Operator("bitXOr", "^", 6),
	new Operator("bitOr", "|", 5),

	new Operator("nullOr", "??", 4),

	new Operator("logicAnd", "&&", 3),
	new Operator("logicOr", "||", 2),

	new Operator("assign", "=", 1),
	new Operator("addAssign", "+=", 1),
	new Operator("subtractAssign", "-=", 1),
	new Operator("multiplyAssign", "*=", 1),
	new Operator("divideAssign", "/=", 1),
	new Operator("modulusAssign", "%=", 1),
	new Operator("shiftLeftAssign", "<<=", 1),
	new Operator("shiftRightAssign", ">>=", 1),
	new Operator("bitAndAssign", "&=", 1),
	new Operator("bitXOrAssign", "^=", 1),
	new Operator("bitOrAssign", "|=", 1)
];

final SuffixOperators: Array<Operator> = [
	new Operator("decrement", "--", 16),
	new Operator("increment", "++", 16)
];

final CallOperators: Array<CallOperator> = [
	new CallOperator("call", "(", ")", 16),
	new CallOperator("arrayAccess", "[", "]", 16)
];

class Operator {
	public var name(default, null): String;
	public var op(default, null): String;
	public var priority(default, null): Int;
	
	public function new(name: String, op: String, priority: Int) {
		this.name = name;
		this.op = op;
		this.priority = priority;
	}
}

class CallOperator extends Operator {
	public var opEnd(default, null): String;

	public function new(name: String, op: String, opEnd: String, priority: Int) {
		super(name, op, priority);
		this.opEnd = opEnd;
	}
}

#end
