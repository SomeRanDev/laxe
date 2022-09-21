package laxe.ast;

#if (macro || laxeRuntime)

final PrefixOperators: Array<Operator> = [
	new Operator("positive", "-", 16),
	new Operator("negative", "+", 16),
	new Operator("logicNot", "!", 16),
	new Operator("logicNot2", "not", 16, true),
	new Operator("bitNot", "~", 16),
	new Operator("preDecrement", "--", 16),
	new Operator("preIncrement", "++", 16),
	new Operator("spread", "...", 16)
];

final IntervalOperator = new Operator("interval", "...", 17);

final InfixOperators: Array<Operator> = [
	new Operator("dotAccess", ".", 19),
	#if (haxe_ver >= 4.3)
	new Operator("safeDotAccess", "?.", 19),
	#end

	new Operator("multiply", "*", 16),
	new Operator("divide", "/", 16),
	new Operator("modulus", "%", 16),

	new Operator("add", "+", 15),
	new Operator("subtract", "-", 15),

	new Operator("shiftLeft", "<<", 14),
	new Operator("shiftRight", ">>", 14),

	new Operator("spaceship", "<=>", 13),

	new Operator("lessThen", "<", 11),
	new Operator("lessThanOrEqual", "<=", 11),
	new Operator("greaterThan", ">", 11),
	new Operator("greaterThanOrEqual", ">=", 11),

	new Operator("equals", "==", 10),
	new Operator("notEquals", "!=", 10),

	new Operator("bitAnd", "&", 9),
	new Operator("bitXOr", "^", 8),
	new Operator("bitOr", "|", 7),

	new Operator("nullOr", "??", 5),

	new Operator("logicAnd", "&&", 4),
	new Operator("logicAnd2", "and", 4, true),
	new Operator("logicOr", "||", 3),
	new Operator("logicOr2", "or", 3, true),

	IntervalOperator,
	new Operator("in", "in", 2, true),

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
	new Operator("bitOrAssign", "|=", 1),

	new Operator("fatArrow", "=>", 1)
];

final SuffixOperators: Array<Operator> = [
	new Operator("decrement", "--", 18),
	new Operator("increment", "++", 18)
];

final CallOperators: Array<CallOperator> = [
	new CallOperator("call", "(", ")", 18),
	new CallOperator("arrayAccess", "[", "]", 18)
];

class Operator {
	public var name(default, null): String;
	public var op(default, null): String;
	public var priority(default, null): Int;
	public var identifierCheck(default, null): Bool;
	
	public function new(name: String, op: String, priority: Int, identifierCheck: Bool = false) {
		this.name = name;
		this.op = op;
		this.priority = priority;
		this.identifierCheck = identifierCheck;
	}

	public function check(parser: laxe.parsers.Parser) {
		if(identifierCheck) {
			return parser.checkAheadIdent(this.op);
		}
		return parser.checkAhead(this.op);
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
