// this is basically a hashlink's main.c copy-pasta with some Godot integration

#include <hl.h>
#include <hlmodule.h>
#include <gdnative/gdnative.h>
#include "gdnative.h"

#ifdef HL_WIN
#	include <locale.h>
typedef uchar pchar;
#define pprintf(str,file)	uprintf(USTR(str),file)
#define pfopen(file,ext) _wfopen(file,USTR(ext))
#define pcompare wcscmp
#define ptoi(s)	wcstol(s,NULL,10)
#define PSTR(x) USTR(x)
#else
typedef char pchar;
#define pprintf printf
#define pfopen fopen
#define pcompare strcmp
#define ptoi atoi
#define PSTR(x) x
#endif

extern void *hl_callback( void *f, hl_type *t, void **args, vdynamic *ret );

static hl_code *load_code( const pchar *file ) {
	hl_code *code;
	FILE *f = pfopen(file,"rb");
	int pos, size;
	char *fdata;
	if( f == NULL ) {
		pprintf("File not found '%s'\n",file);
		return NULL;
	}
	fseek(f, 0, SEEK_END);
	size = (int)ftell(f);
	fseek(f, 0, SEEK_SET);
	fdata = (char*)malloc(size);
	pos = 0;
	while( pos < size ) {
		int r = (int)fread(fdata + pos, 1, size-pos, f);
		if( r <= 0 ) {
			pprintf("Failed to read '%s'\n",file);
			return NULL;
		}
		pos += r;
	}
	fclose(f);
	code = hl_code_read((unsigned char*)fdata, size);
	free(fdata);
	return code;
}

#ifdef HL_VCC
static int throw_handler( int code ) {
	switch( code ) {
	case EXCEPTION_ACCESS_VIOLATION: hl_error("Access violation");
	case EXCEPTION_STACK_OVERFLOW: hl_error("Stack overflow");
	default: hl_error("Unknown runtime error");
	}
	return EXCEPTION_CONTINUE_SEARCH;
}

// this allows some runtime detection to switch to high performance mode
__declspec(dllexport) DWORD NvOptimusEnablement = 1;
__declspec(dllexport) int AmdPowerXpressRequestHighPerformance = 1;

#endif

void GDN_EXPORT godot_gdnative_init(godot_gdnative_init_options *o) {
	set_godot_gdnative_api_struct(o->api_struct);

	struct {
		hl_code *code;
		hl_module *m;
		vdynamic *exc;
	} ctx;
	hl_trap_ctx trap;
#	ifdef HL_WIN
	setlocale(LC_CTYPE,""); // printf to current locale
#	endif
	hl_global_init(&ctx);
	ctx.code = load_code(PSTR("main.hl"));
	ctx.m = hl_module_alloc(ctx.code);
	hl_module_init(ctx.m, NULL);
	hl_code_free(ctx.code);
	hl_trap(trap, ctx.exc, on_exception);
#	ifdef HL_VCC
	__try {
#	endif
		hl_callback(ctx.m->functions_ptrs[ctx.m->code->entrypoint],ctx.code->functions[ctx.m->functions_indexes[ctx.m->code->entrypoint]].type,NULL,NULL);
#	ifdef HL_VCC
	} __except( throw_handler(GetExceptionCode()) ) {}
#	endif
	hl_module_free(ctx.m);
	hl_free(&ctx.code->alloc);
	hl_global_free();
	return;
on_exception:
	{
		varray *a = hl_exception_stack();
		int i;
		uprintf(USTR("Uncaught exception: %s\n"), hl_to_string(ctx.exc));
		for(i=0;i<a->size;i++)
			uprintf(USTR("Called from %s\n"), hl_aptr(a,uchar*)[i]);
		hl_debug_break();
	}
	hl_global_free();
}
