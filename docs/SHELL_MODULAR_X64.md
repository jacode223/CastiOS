# Shell modular de CastiOS x64

La shell x64 tiene una tabla de módulos enlazados en el kernel. Cada descriptor registra nombre, prompt y una función que decide si admite un comando; la ejecución de comandos existente es compartida. Se puede cambiar el módulo activo sin reiniciar:

- `shell list` muestra los módulos disponibles.
- `shell classic` activa la interfaz y los comandos habituales.
- `shell rescue` activa el modo de recuperación: permite `help`, `uname`, `mem`, `disks`, `ps`, `mount`, `ls`, `cat`, `pwd`, `cd`, `stat`, `reboot` y `halt`. Otros comandos se rechazan.
- `shell` muestra las opciones.

El cambio dura hasta el reinicio. `rescue` es una ayuda de operación, no un mecanismo de seguridad: cualquiera puede regresar a `classic` y no sustituye permisos ni aislamiento. Los módulos classic y rescue se incluyen al compilar. También se pueden crear y ejecutar shells CPL3 almacenadas en HSFS; consulte SHELL_USUARIO_X64.md. Para agregar un módulo se añade un descriptor y su filtro en `src/x64/shell64.asm`, y se incrementa SHELL64_COUNT.

La ABI de syscalls sigue usando `int 0x80`; se conservan números anteriores y se completan 26–30 para información de consola y versión. La syscall 1 ahora acepta buffers completos dentro de la página de código, datos o pila del proceso, y rechaza cruces a páginas no válidas o memoria del kernel. Consulte `SYSCALLS_X64_50.md`.

Prueba en QEMU tras compilar: `python3 tools/test_shell64_vm.py`. La prueba `syscheck` comprueba las llamadas, la escritura desde datos y pila y los límites de punteros.
