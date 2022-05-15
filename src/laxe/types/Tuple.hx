package laxe.types;

#if (macro || laxeRuntime)

using StringTools;

import haxe.macro.Context;
import haxe.macro.Expr;

class Tuple {
	public static var minElements = 2;
	public static var maxElements = 26;

	static var emptyPosition: Null<Position> = null;
	static var tuplesCreated = [];
	static var namedTuplesCreated: Map<String, String> = [];
	static var namedTuplesCounter: Array<Int> = [];

	static function ensureEmptyPosition() {
		if(emptyPosition == null) {
			emptyPosition = Context.makePosition({ min: 0, max: 0, file: "" });
		}
	}

	public static function ensure(size: Int) {
		ensureEmptyPosition();
		if(registerTuple(size)) {
			createTypeDefinition(size);
		}
	}

	static function getComplexTypeNamed(t: ComplexType) {
		final str = haxe.macro.ComplexTypeTools.toString(t);
		return str
			.replace(".", "_")
			.replace("<", "_")
			.replace(">", "_")
			.replace("-", "_");
	}

	static function getNamedTupleName(names: Array<String>, types: Array<ComplexType>) {
		var name = "NamedTuple" + names.length + "_";// + (names.join("_"));
		for(i in 0...names.length) {
			name += (names[i] + "_" + getComplexTypeNamed(types[i])) + (i < names.length - 1 ? "_" : "");
		}
		return name;
	}

	public static function ensureNamed(names: Array<String>, types: Array<ComplexType>): TypePath {
		final size = names.length;
		ensure(size);

		final typeParams: Array<TypeParamDecl> = [];
		for(i in 0...size) {
			final typeName = String.fromCharCode(65 + i);
			typeParams.push({ name: typeName });
		}

		final name = getNamedTupleName(names, types);
		final key = names.join("|");
		if(!namedTuplesCreated.exists(key)) {
			final complexType = TPath(generateTypePath(size, types.map(t -> TPType(t))));

			final fields = [];
			var i = 0;
			for(n in names) {
				final path = {
					pack: [],
					name: typeParams[i].name
				}

				fields.push({
					pos: emptyPosition,
					name: n,
					kind: FProp("get", "set", types[i], null),
					access: [APublic]
				});

				final icomp = "_" + i;
				(i++);

				fields.push({
					pos: emptyPosition,
					name: "get_" + n,
					kind: FFun({
						args: [],
						expr: macro return this.$icomp
					}),
					access: [APublic, AInline]
				});

				fields.push({
					pos: emptyPosition,
					name: "set_" + n,
					kind: FFun({
						args: [{ name: "v" }],
						expr: macro @:privateAccess return this.$icomp = v
					}),
					access: [APublic, AInline]
				});
			}

			fields.push({
				pos: emptyPosition,
				name: "unnamed",
				kind: FFun({
					args: [],
					ret: complexType,
					expr: macro @:privateAccess return this
				}),
				access: [APublic, AInline]
			});

			final abstractTypeDef = {
				pos: emptyPosition,
				pack: [],
				name: name,
				meta: [ { name: ":forward", pos: emptyPosition } ],
				fields: fields,
				kind: TDAbstract(complexType, [complexType], [complexType])
			};

			Context.defineModule("laxe.Tuple", [ abstractTypeDef ]);
		}

		return {
			pack: ["laxe"],
			name: "Tuple",
			sub: name
		};
	}

	static function generateTypePath(paramsLength: Int, params: Null<Array<TypeParam>> = null): TypePath {
		return {
			pack: ["laxe"],
			name: "Tuple",
			sub: "Tuple" + paramsLength,
			params: params
		};
	}

	public static function makeTupleExpr(params: Array<Expr>, pos: Position): Expr {
		final paramsLength = params.length;

		if(paramsLength < minElements || paramsLength > maxElements) {
			return { expr: EConst(CIdent("null")), pos: pos };
		}

		ensure(paramsLength);

		final result = {
			expr: ENew(generateTypePath(paramsLength), params),
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

	static function createTypeDefinition(paramCount: Int) {
		final typeParams = [];

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
			kind: TDClass(null, null, false, false, false)
		});

		Context.defineModule("laxe.Tuple", typeDefinitions);
	}
}

#end
