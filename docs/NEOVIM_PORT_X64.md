# Estado del port de Neovim original

Neovim NO está portado ni incluido en esta versión. El código fuente original y sus dependencias no están incorporados. El Castic de esta versión no es un compilador de C ni puede compilar Neovim.

La guía oficial de Neovim enumera dependencias como libuv, LuaJIT, libluv, utf8proc, unibilium, lpeg y Tree-sitter; también requiere su árbol runtime. Consulta https://github.com/neovim/neovim/blob/master/BUILD.md para los requisitos de la revisión que se quiera portar.

La rama x64 actual no ofrece un entorno POSIX ni un ejecutable ELF general, libc, terminal virtual, memoria dinámica de tamaño práctico, procesos e IPC suficientes, sistema de archivos con descriptores completos ni una cadena C/C++ para programas de usuario. Su formato CSH1 está limitado a una página de código. No se puede ejecutar un binario de Neovim para Linux simplemente copiándolo al disco. El editor i386 del proyecto tampoco es Neovim.

Orden propuesto de port:

1. Definir y probar ABI de usuario x64, espacios de memoria dinámicos, reservas y recuperación de procesos.
2. Cargador ELF64, compilador cruzado C/C++, enlazado, libc compatible y syscalls de archivos (open/read/write/seek/stat/close), directorios y errores coherentes.
3. Consola virtual con cursor, dimensiones, secuencias ANSI, entrada por teclado y PTY/termios suficientes.
4. Relojes, polling de eventos, señales y primitivas necesarias para libuv; sistema de ficheros y procesos adecuados para su runtime.
5. Construir y probar primero dependencias (incluyendo LuaJIT, libuv y las versiones requeridas) con configuración de CastiOS y sus licencias.
6. Obtener una revisión original de Neovim y su runtime, realizar el port, ejecutar sus pruebas y validar un arranque y edición reales en una máquina virtual.

Es una línea de desarrollo considerable. No se ha verificado compatibilidad con Neovim ni con ninguna de sus dependencias.
