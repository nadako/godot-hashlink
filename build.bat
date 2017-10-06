@echo off
call "C:\Program Files (x86)\Microsoft Visual Studio 14.0\VC\vcvarsall.bat"
cd embed
cl /DWIN32 /DNDEBUG /D_CONSOLE /ID:\Code\hashlink\src /c D:\Code\hashlink\src\callback.c D:\Code\hashlink\src\code.c D:\Code\hashlink\src\jit.c D:\Code\hashlink\src\module.c D:\Code\hashlink\src\debugger.c
cl /DWIN32 /DNDEBUG /D_CONSOLE /ID:\Code\hashlink\src /ID:\Code\godot\modules\gdnative\include /c gdnative.c main.c
link /DLL /OUT:test.hdll *.obj D:\Code\hashlink\Debug\libhl.lib user32.lib
