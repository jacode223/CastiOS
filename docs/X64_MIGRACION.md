# Migracion x86-64 de CastiOS

## Estado comprobado

La preview incluye un driver ATA PIO de lectura LBA28 para el disco IDE
primario maestro (hda). `mount` lee las copias HSFS5 situadas en 16 y 20 MiB,
comprueba cabecera y checksum y utiliza la copia válida de mayor generación.
`ls [ruta]`, `cd ruta` y `cat ruta` aceptan rutas absolutas y relativas,
incluyendo `.` y `..`. `cat` lee archivos de texto HSFS de varios extents y
archivos grandes tipo 5 desde sus sectores externos, hasta 100 MiB. Los
metadatos ocupan 3,75 MiB en RAM; la región debe figurar como disponible en
E820. ATA tiene esperas acotadas. No hay escrituras, creación, borrado,
permisos persistentes ni montaje AHCI o USB en x64.

Para VirtualBox: arranca la ISO preview con un disco CastiOS existente
conectado como IDE primario maestro. Ejecuta `mount`, después `ls /` o
`cat /docs/nota.txt`. Esto lee el disco pero no lo modifica. En QEMU,
`tools/test_x64_hsfs.py` prueba archivos, carpetas, extents, archivos grandes,
recuperación usando el espejo y rechazo de copias corruptas.

`src/x64/kernel.asm` es un nuevo objetivo, sin cargar el kernel i386 ni usar
su ABI de 32 bits. GRUB Multiboot1 entra por un trampolin de 32 bits; CPUID
exige PAE y long mode; tres niveles de tablas PML4/PDPT/PD hacen un mapa
identidad de 1 GiB con paginas de 2 MiB. Al entrar en 64 bits se instalan
GDT de 64 bits, IDT para excepciones, pila privada y una consola VGA texto
con teclado PS/2 en sondeo. E9 emite el mismo texto para la prueba QEMU.
El asignador lee regiones disponibles del mapa E820 y entrega marcos de
4 KiB por encima de 16 MiB y por debajo de 1 GiB. Hay dos espacios CPL3:
cada uno tiene PML4, PDPT, PD, PT, código, datos y pila privados. Ambos usan
las mismas direcciones virtuales desde `0x40000000`; sus páginas físicas son
distintas. El código es de solo lectura para el usuario y hay una página de
guardia entre datos y pila. El primer GiB es solo supervisor; el TSS usa una
pila de entrada a CPL0 distinta para cada tarea.

El PIT y PIC remapeado generan IRQ0 a unos 100 Hz. El manejador guarda
registros y marco IRET, cambia CR3 y pila de kernel y reanuda otra tarea.
`multi64` comprueba el número de cambios y que dos tareas con la misma
dirección virtual de datos conservan valores diferentes. Si una sale o falla,
la otra sigue; datos y pila se ponen a cero antes de cada lanzamiento.

La shell ofrece `help`, `uname`, `mem`, `frames`, `multi64`, `multifault64`,
`users`, `groups`, `perms`, `rootcred`, `guestcred`, `groupcred` y las pruebas
`run64`, `fault64`, `badptr64`, `ud64`, `io64`, `reboot`, `halt`.
`run64` carga una tarea de prueba
de 64 bits, que escribe texto por una syscall con puntero/longitud comprobados
y termina con código 42. Los otros comandos comprueban fallo de página,
puntero a memoria del kernel, opcode ilegal y acceso prohibido a puertos de
E/S. La consola sigue viva después. No hay todavía carga de archivos:
las tareas de prueba vienen incluidas en la ISO.

Las identidades están fijadas en el kernel: `root` UID/GID 0/0 y `alice`
1000/100. Grupos `system` GID 0 y `users` GID 100. La syscall 4 accede al
recurso de diagnóstico `root:system 0600`; la 5 al registro `root:users
0660`. Una función común compara UID, GID y bits rwx; root puede omitir
esta comprobación discrecional. El kernel asigna las credenciales por ranura;
una tarea no puede indicar un UID propio al llamar la syscall. `guestcred`
verifica denegación `-13` y `groupcred` acceso por GID. La shell es root y
puede lanzar ambas pruebas; no hay contraseña, inicio de sesión, usuarios
editables, grupos suplementarios ni metadatos persistentes.

La ISO `CastiOS-x64-preview.iso` se construye con `tools/build_x64.py`.
`tools/test_x64.py` verifica por QMP CS64, IRQ0, dos salidas y preempción,
aislamiento de datos, recuperación tras un fallo, permisos por UID/GID,
errores CPL3 y regreso a la shell. El arranque de 32 bits
sigue siendo la opción funcional.

## Trabajo restante para una migracion completa

1. Ampliar el asignador E820 para liberar marcos, soportar RAM por encima de
   1 GiB y dejar el mapa identidad temporal. El planificador tiene dos tareas
   integradas en el kernel, sin carga de programas externos ni FPU/SSE.
2. Portar más IRQ y recursos por proceso; la shell y drivers todavía corren
   en CPL0, con syscalls de prueba para texto y permisos sobre dos recursos.
3. Añadir AHCI, LBA48 y escritura HSFS transaccional con recuperación tras
   interrupciones, además de permisos de archivos y actualización A/B.
4. Portar servicios C, framebuffer, teclado USB, ratón y escritorio. Su
   `ext_api` usa punteros/ABI i386 y no puede enlazarse tal cual.
5. Definir formato de apps y Speed de 64 bits. AX05 y Speed actuales son
   código i386 y no se ejecutan en esta ISO. PE32+ solo podrá abordarse
   después de disponer de procesos CPL3 y un cargador validado.

La ISO preview no instala ni escribe datos. El build HDD i386 sigue siendo el
que permite editar archivos, recuperar y actualizar CastiOS.
