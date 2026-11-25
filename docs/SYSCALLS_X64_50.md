# CastiOS x86-64: tabla inicial de 50 syscalls

Interfaz experimental `int 0x80`: RAX indica el número, argumentos en
RDI/RSI/RDX/RCX, y RAX devuelve resultado o error negativo. La tabla tiene
50 entradas numeradas 0..49; **32 tienen implementación** y las 18 restantes
devuelven `-38` (ENOSYS). Un número >=50 también devuelve ENOSYS. El ABI es
propio de CastiOS, no es el ABI de Linux y puede evolucionar.

| Nº | Llamada | Alcance |
|---:|---|---|
| 0 | exit | Terminar tarea CPL3 con código RDI |
| 1 | console_write | Escribir hasta 256 bytes desde código, datos o pila del proceso |
| 2 | getuid | UID fijo de la tarea |
| 3 | getgid | GID fijo de la tarea |
| 4 | admin_demo | Recurso de ejemplo, acceso root |
| 5 | group_demo | Recurso de ejemplo, acceso por grupo |
| 6 | file_read | Leer hasta 512 bytes HSFS6.1 a la página de datos |
| 7 | file_write_text | Crear o reemplazar texto corto; solo UID 0 |
| 8 | getpid | PID de CastiPS |
| 9 | yield | Ceder CPU entre tareas activas |
| 10 | getppid | PID de la tarea padre |
| 11 | uptime_ticks | Ticks PIT desde el arranque |
| 12 | process_ticks | Ticks de la tarea actual |
| 13 | getpagesize | Devuelve 4096 |
| 14 | fs_mounted | 1 si HSFS6 está montado, 0 si no |
| 15 | fs_capacity | Sectores del volumen montado, o ENODEV |
| 16 | disk_backend | 0 IDE; 1 AHCI seleccionado |
| 17 | disk_read_errors | Intentos de lectura fallidos desde el arranque |
| 18 | disk_read_retries | Reintentos IDE efectuados |
| 19 | file_size | Longitud del archivo HSFS6.1 con permiso de lectura |
| 20 | process_state | Estado del propio PID; otros PID devuelven EACCES |
| 21 | mouse_x | Posición X del ratón PS/2, o ENODEV |
| 22 | mouse_y | Posición Y del ratón PS/2, o ENODEV |
| 23 | mouse_buttons | Máscara de botones PS/2, o ENODEV |
| 24 | mouse_ready | 1 si el ratón se inicializó, 0 si no |
| 25 | mouse_events | Cantidad de paquetes procesados, o ENODEV |
| 26 | abi_version | Versión del ABI: 1 |
| 27 | console_size | Columnas en 32 bits bajos, filas en 32 bits altos |
| 28 | framebuffer_width | Anchura en píxeles o ENODEV |
| 29 | framebuffer_height | Altura en píxeles o ENODEV |
| 30 | shell_id | Shell activa: 0 classic, 1 rescue |
| 31 | keyboard_poll | Tecla ASCII sin bloqueo, -11 si no hay datos, -16 en multitarea |
| 32..49 | reservadas | ENOSYS; aún no existen open, close, fork o exec |

Las cadenas de 6, 7 y 19 deben estar en la página de código privada de la
tarea. Para 6, RDI es ruta, RSI destino en página de datos, RDX número de
bytes y RCX desplazamiento. La 7 acepta RDI ruta y RSI texto en la página de
código. Para 19, RDI es ruta. La 20 recibe PID en RDI. Los buffers se
comprueban antes de utilizarlos y la lectura respeta UID/GID/modo. Las tareas
de prueba usan el directorio de trabajo global de la shell: aún no hay cwd
por proceso ni usuarios con autenticación.

`syscheck` ejecuta una tarea CPL3 que prueba identidad, límites y ENOSYS para
las 18 posiciones reservadas. La syscall 31 sondea el teclado PS/2 y procesa paquetes de ratón cuando aparecen. No es una lectura bloqueante ni proporciona entrada USB.
`tools/test_castips_vm.py` y
`tools/test_hsfs61_vm.py` ejercitan procesos y las syscalls de archivos en QEMU.

El lector de sectores IDE reintenta una vez una lectura fallida y cuenta
errores y reintentos visibles en `disks` y llamadas 17..18. AHCI no se
reintenta tras error: mantiene su puerto deshabilitado para evitar reutilizar
memoria mientras puede quedar DMA activo. No hay recuperación automática de
desconexión, LBA48 para IDE ni escritura AHCI. Los contadores se reinician con
el sistema. Las pruebas no inyectan fallos físicos de disco.
