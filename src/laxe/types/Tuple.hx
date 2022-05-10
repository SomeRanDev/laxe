package laxe.types;

#if (macro || laxeRuntime)

import haxe.macro.Context;
import haxe.macro.Expr;

class Tuple {
	public static var minElements = 2;
	public static var maxElements = 26;

	static var emptyPosition: Null<Position> = null;
	static var tuplesCreated = [];

	public static function makeTupleExpr(params: Array<Expr>, pos: Position): Expr {
		if(emptyPosition == null) {
			emptyPosition = Context.makePosition({ min: 0, max: 0, file: "" });
		}

		if(params.length < minElements || params.length > maxElements) {
			return { expr: EConst(CIdent("null")), pos: pos };
		}

		if(registerTuple(params.length)) {
			createTypeDefinition(params);
		}

		final result = {
			expr: ENew({
				pack: ["laxe"],
				name: "Tuple",
				sub: "Tuple" + params.length
			}, params),
			pos: pos
		};

		return result;
	}

	static function registerTuple(index: Int) {
		while(tuplesCreated.length <= index) {
			tuplesCreated.push(false);
		}
		if(tuplesCreated[index]) {
			return false;
		}
		tuplesCreated[index] = true;
		return true;
	}

	static function createTypeDefinition(params: Array<Expr>) {
		final typeParams = [];

		final paramCount = params.length;

		final fields = [];

		final toString = [];
		final newArgs = [];
		final newExprs = [];
		final createExprsArgs = [];

		for(i in 0...paramCount) {
			final typeName = String.fromCharCode(65 + i);

			typeParams.push({
				name: typeName
			});

			toString.push("${this._" + i + "}");

			final type = TPath({
				sub: null,
				params: null,
				pack: [],
				name: typeName
			});

			fields.push({
				name: "_" + i,
				pos: emptyPosition,
				meta: null,
				doc: null,
				access: [APublic],
				kind: FVar(type, null)
			});

			fields.push({
				name: "component" + i,
				pos: emptyPosition,
				meta: null,
				doc: null,
				access: [APublic, AInline],
				kind: FFun({
					ret: type,
					params: null,
					expr: {
						pos: emptyPosition,
						expr: EReturn({
							pos: emptyPosition,
							expr: EConst(CIdent("_" + i))
						})
					},
					args: []
				})
			});

			newArgs.push({
				name: "_in" + i,
				type: type
			});

			newExprs.push({
				pos: emptyPosition,
				expr: EBinop(OpAssign, {
					pos: emptyPosition,
					expr: EConst(CIdent("_" + i))
				}, {
					pos: emptyPosition, 
					expr: EConst(CIdent("_in" + i))
				})
			});

			createExprsArgs.push({
				pos: emptyPosition,
				expr: EConst(CIdent("_in" + i))
			});
		}

		fields.push({
			name: "new",
			pos: emptyPosition,
			meta: null,
			doc: null,
			access: [APublic, AInline],
			kind: FFun({
				ret: null,
				params: null,
				expr: {
					pos: emptyPosition,
					expr: EBlock(newExprs)
				},
				args: newArgs
			})
		});

		fields.push({
			name: "toString",
			pos: emptyPosition,
			meta: [{ name: ":keep", pos: emptyPosition }],
			doc: null,
			access: [APublic, AInline],
			kind: FFun({
				ret: null,
				params: null,
				expr: {
					pos: emptyPosition,
					expr: EReturn({
						pos: emptyPosition,
						expr: EConst(CString("(" + toString.join(", ") + ")", SingleQuotes))
					})
				},
				args: []
			})
		});

		final typeDefinitions: Array<TypeDefinition> = [];

		typeDefinitions.push({
			pos: emptyPosition,
			params: typeParams,
			pack: [],
			name: "Tuple" + paramCount,
			meta: [
				{ name: ":generic", pos: emptyPosition },
				{ name: ":struct", pos: emptyPosition },
				{ name: ":nativeGen", pos: emptyPosition }
			],
			isExtern: false,
			fields: fields,
			kind: TDClass(null, [], false, false, false)
		});

		Context.defineModule("laxe.Tuple", typeDefinitions);
	}
}

#end
