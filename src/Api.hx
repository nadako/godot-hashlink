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
		var glueClass = macro class Glue {
			static function destroy(obj:GodotObject):Void;
		}
		glueClass.isExtern = true;
		glueClass.meta = [{name: ":hlNative", pos: null, params: [macro "godot"]}];
		var glueC = [
			"#define HL_NAME(n) glue_##n",
			"#include <hl.h>",
			""
		];

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
				var factoryMethodName = '${className}_new';
				glueClass.fields.push({
					pos: null,
					name: factoryMethodName,
					kind: FFun({args: [], ret: macro : GodotObject, expr: null}),
					access: [AStatic],
				});
				if (superClass == null)
					classFields.push({
						pos: null,
						name: "__obj",
						access: [],
						kind: FVar(macro : GodotObject, null)
					});
				classFields.push({
					pos: null,
					name: "__construct",
					access: [],
					kind: FFun({
						args: [],
						ret: macro : GodotObject,
						expr: macro return __create_object()
					})
				});
				classFields.push({
					pos: null,
					name: "__create_object",
					access: [AStatic],
					kind: FFun({
						args: [],
						ret: macro : GodotObject,
						expr: macro return Glue.$factoryMethodName()
					})
				});
				// @:hlNative("std", "file_open") static function file_open( path : hl.Bytes, mode : Int, binary : Bool ) : FileHandle { return null; }
				classFields.push({
					pos: null,
					name: "new",
					access: [APublic],
					kind: FFun({
						args: [],
						ret: null,
						expr: if (superClass != null) macro super() else macro __obj = __construct()
					})
				});

				// TODO: a single should be enough?
				classFields.push({
					pos: null,
					name: "destroy",
					access: if (superClass != null) [APublic, AOverride] else [APublic],
					kind: FFun({
						args: [],
						ret: null,
						expr: macro Glue.destroy(__obj)
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

				var methodName = escapeIdent(m.name);
				var nativeMethodName = '${className}_${methodName}';
				var expr = macro Glue.$nativeMethodName();
				var isVoid = m.return_type == "void";

				classFields.push({
					pos: null,
					name: methodName,
					access: if (c.singleton) [APublic, AStatic, AInline] else [APublic, AInline],
					kind: FFun({
						args: args,
						ret: convertType(m.return_type),
						expr: if (isVoid) expr else macro return $expr
					})
				});

				glueClass.fields.push({
					pos: null,
					name: nativeMethodName,
					kind: FFun({args: [], ret: convertType(m.return_type), expr: null}),
					access: [AStatic],
				});

				glueC.push('HL_PRIM void HL_NAME($nativeMethodName)(godot_object *__obj) {');
				glueC.push('\tstatic godot_method_bind *mb = NULL;');
				glueC.push('\tif (mb == NULL)');
				glueC.push('\t\tmb = godot_method_bind_get_method("${c.name}", "${m.name}");');
				glueC.push('\tgodot_method_bind_ptrcall(mb, __obj, TODO, TODO);');
				glueC.push('}');
				glueC.push("");
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
					switch f.kind {
						case FFun(_):
							if (f.name != "new" && f.name != "destroy" && f.access.indexOf(AStatic) == -1)
								parentFields.set(f.name, true);
						case _:
					}
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

		var output = [
			"import godot.*;",
			printer.printTypeDefinition(glueClass, false)
		];
		sys.io.File.saveContent('Glue.hx', output.join("\n"));

		sys.io.File.saveContent('glue.c', glueC.join("\n"));
	}
}
