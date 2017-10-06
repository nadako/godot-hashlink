@:hlNative("test")
extern class Godot {
	static inline function greet(s:String):Void say_with_godot(@:privateAccess s.bytes, s.length);

	static function say_with_godot(b:hl.Bytes, l:Int):Void;
}

class Main {
	static function main() {
		for (i in 0...10)
			Godot.greet('$i Hi from Haxe (привет from unicode)!');
	}
}
