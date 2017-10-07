import haxe.DynamicAccess;
import haxe.macro.Expr;
using StringTools;

typedef GClass = {
	var name:String;
	var base_class:String;
	var instanciable:Bool;
	var singleton:Bool;
	var methods:Array<GMethod>;
	var enums:Array<GEnum>;
	var constants:DynamicAccess<Int>;
}

typedef GMethod = {
	var name:String;
	var arguments:Array<GArgument>;
	var return_type:String;
}

typedef GArgument = {
	var name:String;
	var type:String;
}

typedef GEnum = {
	var name:String;
	var values:DynamicAccess<Int>;
}

class Api {
	static function stripName(n:String)
		return if (n.charCodeAt(0) == "_".code) n.substring(1) else n;

	static function escapeIdent(n:String)
		return switch n {
			case "import": "import_";
			case "new": "new_";
			case "class": "class_";
			case "var": "var_";
			case "default": "default_";
			case "in": "in_";
			case "function": "function_";
			case _: n;
		}

	static function convertType(t:String):ComplexType {
		return switch t {
			case "void": macro : Void;
			case "float": macro : Float;
			case "int": macro : Int;
			case "bool": macro : Bool;
			case _ if (t.startsWith("enum.")):
				t = t.substring("enum.".length);
				var parts = t.split("::");
				var name = parts.map(stripName).join("");
				TPath({pack: [], name: name});
			case _:
				TPath({pack: [], name: stripName(t)});
		}
	}

	static function main() {
		var classes:Array<GClass> = haxe.Json.parse(sys.io.File.getContent("api.json"));

		var printer = new haxe.macro.Printer();
		var outputClasses = new Map<String,{t:TypeDefinition, p:Null<TypePath>, e:Array<TypeDefinition>}>();

		for (c in classes) {
			var className = stripName(c.name);
			var classFields = new Array<Field>();
			var superClass = if (c.base_class == "") null else {pack: [], name: stripName(c.base_class)};
			var enums = new Array<TypeDefinition>();

			for (e in c.enums) {
				enums.push({
					pos: null,
					pack: [],
					name: className + stripName(e.name),
					kind: TDAbstract(macro : Int, [macro : Int], [macro : Int]),
					meta: [{name: ":enum", pos: null}],
					fields: [for (key in e.values.keys()) {
						{
							pos: null,
							name: key,
							kind: FVar(null, {pos: null, expr: EConst(CInt(Std.string(e.values[key])))})
						}
					}]
				});
			}

			for (name in c.constants.keys()) {
				classFields.push({
					pos: null,
					name: name,
					access: [APublic,AStatic,AInline],
					kind: FVar(null, {pos: null, expr: EConst(CInt(Std.string(c.constants[name])))})
				});
			}

			if (c.instanciable) {
				classFields.push({
					pos: null,
					name: "new",
					access: [APublic],
					kind: FFun({
						args: [],
						ret: null,
						expr: if (superClass != null) macro super() else macro {}
					})
				});
				classFields.push({
					pos: null,
					name: "destroy",
					access: if (superClass != null) [APublic, AOverride] else [APublic],
					kind: FFun({
						args: [],
						ret: null,
						expr: macro {}
					})
				});
			}

			for (m in c.methods) {
				var args:Array<FunctionArg> = [for (arg in m.arguments) {
					{
						name: escapeIdent(arg.name),
						type: convertType(arg.type),
					}
				}];

				classFields.push({
					pos: null,
					name: escapeIdent(m.name),
					access: if (c.singleton) [APublic, AStatic] else [APublic],
					kind: FFun({
						args: args,
						ret: convertType(m.return_type),
						expr: macro throw "TODO"
					})
				});
			}

			var classDef:TypeDefinition = {
				pos: null,
				pack: [],
				name: className,
				kind: TDClass(superClass),
				fields: classFields,
			};
			outputClasses.set(className, {t:classDef, p: superClass, e: enums});
		}

		for (c in outputClasses) {
			var parentFields = new Map();
			var parent = c.p;
			while (parent != null) {
				var c = outputClasses[parent.name];
				for (f in c.t.fields) {
					if (f.name != "new" && f.name != "destroy" && f.access.indexOf(AStatic) == -1)
						parentFields.set(f.name, true);
				}
				parent = c.p;
			}
			for (f in c.t.fields) {
				if (parentFields.exists(f.name)) {
					f.access.push(AOverride);
				}
			}
		}


		if (!sys.FileSystem.exists("godot"))
			sys.FileSystem.createDirectory("godot");

		inline function todo(cl:String) sys.io.File.saveContent('godot/$cl.hx', 'package godot;\n\nclass $cl {} // TODO');
		todo("Variant");
		todo("VariantType");
		todo("VariantOperator");
		todo("Dictionary");
		todo("Array");
		todo("Error");
		todo("NodePath");
		todo("Rect2");
		todo("Rect3");
		todo("RID");
		todo("Color");
		todo("Vector2");
		todo("Vector3");
		todo("Vector3Axis");
		todo("Basis");
		todo("Quat");
		todo("PoolStringArray");
		todo("PoolVector2Array");
		todo("PoolVector3Array");
		todo("PoolColorArray");
		todo("PoolByteArray");
		todo("PoolIntArray");
		todo("PoolRealArray");
		todo("Plane");
		todo("Transform");
		todo("Transform2D");

		for (c in outputClasses) {
			var output = ["package godot;", ""];
			output.push(printer.printTypeDefinition(c.t, false));
			output.push("");
			sys.io.File.saveContent('godot/${c.t.name}.hx', output.join("\n"));
			for (e in c.e) {
				var output = ["package godot;", ""];
				output.push(printer.printTypeDefinition(e, false));
				output.push("");
				sys.io.File.saveContent('godot/${e.name}.hx', output.join("\n"));
			}
		}
	}
}