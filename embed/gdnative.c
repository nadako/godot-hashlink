#define HL_NAME(n) my_##n
#include <hl.h>

#include <gdnative/gdnative.h>
#include <gdnative_api_struct.gen.h>
#include "gdnative.h"

static const godot_gdnative_api_struct * api;

void set_godot_gdnative_api_struct(const godot_gdnative_api_struct * _api) {
	api = _api;
}

HL_PRIM void HL_NAME(say_with_godot)(vbyte * string, int len) {
	godot_string s;
	api->godot_string_new_unicode_data(&s, string, len);
	api->godot_print(&s);
	api->godot_string_destroy(&s);
}
DEFINE_PRIM(_VOID, say_with_godot, _BYTES _I32);
