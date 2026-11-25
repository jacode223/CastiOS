# CastiUSB i386 experimental

Nuevos backends USB xHCI / UHCI, mejoras EHCI y FAT32, optimizacion de RAM.
Consulta [la guia de esta version](docs/CASTIUSB_EXPERIMENTAL.md). `make i386`
construye solo i386; `make test-fat32-large` comprueba FAT32 de 64 GB simulado.

# Cambios i386: USB HID y Castic

La rama i386 incluye teclado y raton USB HID boot en EHCI experimental, y Castic con variables y operaciones enteras. El interprete Speed y su modulo de arranque se han retirado de i386; las secciones historicas inferiores describen versiones anteriores. Consulte docs/USB_HID_I386.md y docs/CASTIC_I386.md.

# Castic 0.1 para i386

`castic fuente.cas salida.app` compila instrucciones `print` a AX05 i386; `exec salida.app` ejecuta el programa en CPL3. Puede editar las fuentes con el editor propio `nano`. Guía y límites: [Castic i386](docs/CASTIC_I386.md). Neovim original todavía no está portado.

# CastiOS x64: ABI de 50 posiciones

Tabla `int 0x80` con 50 posiciones: 26 implementadas y 24 reservadas que
devuelven ENOSYS. Incluye identidad/estado de procesos, tiempos, consultas de
disco y tamaño de archivo. IDE reintenta una lectura fallida una vez y cuenta
fallos y reintentos. Detalles y límites: [syscalls x64](docs/SYSCALLS_X64_50.md).

# HSFS6.1: subcarpetas y archivos de 500 MiB

La shell x64 admite `mkdir`, `cd`, `pwd`, rutas anidadas y copia de archivos
de hasta 500 MiB mediante `cp`, por sectores. La herramienta del host admite
importación/exportación por bloques. Consulta [HSFS6.1](docs/HSFS61.md) para
los límites y requisitos de disco. La copia completa de 500 MiB aún no se ha
terminado de verificar; lectura de 500 MiB y copia de 2 MiB probadas en QEMU.

# CastiPS 0.1: gestor ligero de procesos x86-64

Tabla PCB de 32 entradas (2 usuarios simultaneos), PID, estados, CPU ticks, `ps`, `reap`, syscalls 8 `getpid` y 9 `yield`, con `pidtest64`. Consulte [documentación CastiPS](docs/CASTIPS_0_1.md). `make` compila las ramas originales y ejecuta pruebas estáticas.

# CastiOS x86-64: instalación BIOS experimental

`disks` detecta IDE hda o el AHCI seleccionado con `ahciscan`. En una VM con
un disco IDE vacío, `install` muestra la advertencia y `install hda borrar`
instala el arranque BIOS y HSFS6, borrando los datos existentes en el disco.
AHCI y UEFI aún no se pueden usar para instalar. Más información:
[instalación x64](docs/INSTALACION_X64.md).

# CastiOS x86-64: ratón PS/2 inicial

El controlador propio PS/2 de CastiOS se ha adaptado a x64. `mousestat`
muestra posición y botones; el teclado y el ratón comparten el i8042. La
shell sondea el dispositivo, sin cursor gráfico ni soporte USB. Consulta
[ratón x64](docs/MOUSE_X64.md).

# CastiOS x86-64: AHCI SATA inicial

`ahciscan` detecta el primer disco SATA en el primer controlador AHCI PCI;
después `mount`, `ls` y `cat` permiten leer HSFS6. El driver x64 está adaptado
del código AHCI i386 propio de CastiOS y se ha probado con ICH9-AHCI en QEMU.
AHCI es solo lectura; IDE conserva la escritura limitada de HSFS6. Consulta
[AHCI x64](docs/AHCI_X64.md) para requisitos y límites.

# CastiOS x86-64: HSFS6 experimental

Nuevo formato HSFS6 con longitudes y direcciones de 64 bits, copia de
metadatos y comandos x64 (`mount`, `ls`, `cat`, `stat`, `echo texto > archivo`). Las syscalls
6 y 7 leen y escriben HSFS6 con límites y permisos. El volumen se crea desde el host con `tools/hsfs6.py`.
La escritura en CastiOS acepta una línea corta de texto. El driver IDE limita
el acceso efectivo a 128 GiB con LBA28; no hay subdirectorios. Consulta
[HSFS6](docs/HSFS6.md) para formato, pruebas y límites.

# Historial: CastiOS x86-64 preview con HSFS5

En una preview anterior `mount` buscaba HSFS5 en un disco IDE ATA primario maestro, verificaba las dos
copias de metadatos y monta la copia válida más reciente en solo lectura.
`ls`, `cd` y `cat` permiten explorar rutas y leer textos, incluso por extents
o datos externos de archivos grandes. La copia de metadatos ocupa unos 3,75
MiB de RAM. La shell x64 actual utiliza HSFS6; la versión i386 mantiene HSFS5.

# CastiOS x86-64 preview: multitarea y credenciales de prueba

`bash build.sh` produce `dist/CastiOS-x64-preview.iso` ademas de las
imagenes i386 existentes. La ISO x64 arranca con GRUB, comprueba CPUID,
activa PAE y long mode, mapea el primer GiB con paginas de 2 MiB e instala
una GDT/IDT de 64 bits. La nueva ruta reserva marcos de 4 KiB desde E820.
`multi64` alterna dos tareas CPL3 por IRQ0/PIT con CR3, registros y pila
privados; `multifault64` comprueba que un fallo de una no derriba la otra.
Hay dos identidades fijas (`root` y `alice`) con grupos `system` y `users`;
las syscalls verifican permisos 0600 y 0660 sobre recursos de prueba.
`run64`, `fault64`, `badptr64`, `ud64` e `io64` comprueban también aislamiento.
Prueba: `python3 tools/test_x64.py` en QEMU x86-64.

**No es una conversion completa:** el planificador solo maneja dos tareas
integradas. No hay autenticación, usuarios persistentes ni permisos de archivo
x64: escritura HSFS, framebuffer, drivers adicionales, apps externas, Speed, actualización
A/B y escritorio siguen en la imagen i386 funcional CastiOS 0.36.
Consulta [migracion x64](docs/X64_MIGRACION.md).

# CastiOS 0.36: primer paso hacia compatibilidad Win32

`castctl peinfo RUTA.exe` inspecciona PE32 x86 sin ejecutar el binario:
verifica cabeceras, secciones, direcciones e importaciones y muestra DLL y
funciones necesarias. Rechaza PE32+ x64 y archivos malformados. Por ahora
requiere 200 MiB de RAM y que el archivo mida como máximo 1 MiB. No hay
cargador Win32 ni ejecución de aplicaciones Windows 10; consulta
[alcance y pasos siguientes](docs/WIN32_COMPAT.md).

# CastiOS 0.35: siete mejoras del gestor de ventanas

1. Minimizar sin cerrar ni perder el estado (Ctrl-Y o boton _).
2. Restaurar desde la barra de tareas o con Ctrl-R.
3. Maximizar y volver al tamaño anterior (Ctrl-E o boton +).
4. Redimensionar desde la esquina inferior derecha o con Ctrl-Z/Ctrl-X.
5. Recordar ventanas, foco, carpetas y tamaños al salir con Ctrl-Q y volver
   a `desktop` durante el mismo arranque; no se guarda en disco.
6. Atajos de control integrados con el foco y las ventanas minimizadas.
7. Redibujar solo el cursor cuando se mueve sin arrastrar: respaldo de
   672 bytes, sin otra copia completa de la pantalla.

La geometria queda limitada a la zona de escritorio. El nuevo modulo
`wm/windows.h` gestiona ciclo de vida y limites; el compositor dibuja los
controles y el bucle de entrada resuelve los eventos. Prueba principal:
`tools/test_wm_controls.py`, con eventos reales de QEMU y comprobacion RGB.

# CastiOS 0.34: gestor de ventanas modular

`desktop` permite mantener Archivos, Procesos y Sistema abiertos a la vez.
Cada ventana conserva su estado; el clic y la barra de tareas cambian el foco.
Arrastra la barra de titulo para moverla, o usa WASD. Ctrl-N cambia el foco,
Ctrl-W cierra y Tab abre Inicio. Terminal vuelve a la shell.
Los modulos estan en `src/extensions/wm`: tipos/estado, aplicaciones,
compositor y entrada. Son modulos compilados con el servicio C privilegiado;
no hay carga dinamica ni aislamiento propio de aplicaciones graficas.

# CastiOS 0.33: escritorio con ventanas

`desktop` muestra ahora una barra de tareas, menú Inicio y ventanas de
Archivos, Procesos y Sistema, con foco por teclado y ratón PS/2. Archivos
lista el directorio HSFS actual, permite desplazarse, entrar en carpetas
y leer una vista previa de archivos de texto. Procesos muestra PID y estado
de tareas de fondo. Terminal vuelve a la shell; Esc cierra la ventana y
después sale del escritorio. La interfaz sigue siendo pequeña: sin arrastre
de ventanas, aplicaciones gráficas independientes ni exploración FAT32
dentro de la ventana de Archivos.

# CastiOS 0.32: teclado USB HID funcional

`castctl usbscan` configura la lectura periódica del primer teclado HID boot
de alta velocidad conectado directamente a EHCI. Los informes pasan a la
cola de teclas de la shell: letras, números, modificadores y flechas. Se ha
probado junto a un disco USB FAT32 y con regreso al teclado PS/2 al retirarlo.
`castctl usbkbd` indica si la entrada está activa. No incluye hubs,
teclados de velocidad completa/baja, USB xHCI ni ratón USB.

# CastiOS 0.31: recuperación de discos USB

Los discos USB EHCI ahora intentan recuperarse de errores del transporte
Bulk-Only mediante reset y limpieza de endpoints. Las lecturas reintentan
fallos transitorios y consultan REQUEST SENSE; la desconexión no se confunde
con un error recuperable. `castctl usbinfo` muestra si el puerto sigue
conectado y cuántos fallos se registraron. Tras reconectar, usa
`castctl usbscan` y vuelve a montar el volumen. Sigue siendo FAT32 de solo
lectura en EHCI; no hay aún entrada de teclado USB ni soporte xHCI.

# CastiOS 0.30: ratón PS/2 inicial

El driver `ps2mouse` inicializa el puerto auxiliar del controlador PS/2,
recibe paquetes de tres bytes por IRQ12 y ofrece posición, botones y el
comando `mousestat`. En `desktop`, mover el ratón muestra un cursor sencillo,
señala una opción y el clic izquierdo la abre. El teclado sigue disponible.
No se admiten ratones USB ni rueda; consulta [soporte PS/2](docs/MOUSE.md).

# CastiOS 0.29: primer escritorio de teclado

`desktop` abre un lanzador en el framebuffer RGB32. Las flechas eligen
Terminal, Archivos, Procesos o Sistema; Enter abre la opción y Esc vuelve
a la shell. Archivos, Procesos y Sistema muestran su información en la
terminal existente. El escritorio requiere arranque gráfico; todavía no
hay ventanas independientes ni entrada de ratón.

# CastiOS 0.28: espera individual de tareas de fondo

`wait PID` espera y recoge una tarea concreta, liberando su ranura para otro
`bg` mientras las demás siguen activas. `wait` sin argumentos espera todas.
Los PIDs de fondo avanzan al lanzar tareas y no cambian al reutilizar una
ranura; `kill PID`, `ps` y la syscall `getpid` usan el mismo identificador.
Hay un máximo de cuatro tareas de fondo simultáneas.

# CastiOS 0.27: tareas de fondo cancelables

`ps` muestra las tareas AX05; `kill PID` detiene una tarea `bg` activa o
dormida, libera inmediatamente sus páginas y su descriptor, y conserva el
resultado 143 hasta `wait`. Consulta [procesos y límites](docs/PROCESOS_MEMORIA.md).

# CastiOS 0.26: memoria y permisos AX05

Cuatro páginas de datos por tarea AX05 se asignan al primer acceso; el
código AX05 queda de solo lectura y una app que accede fuera de sus páginas
termina sin parar la shell. `file_write` requiere `chmod APP.app +w` desde
la shell y se revoca con `-w`. Las tareas `bg` liberan páginas y su FD al
acabar. Consulta [alcance y límites](docs/PROCESOS_MEMORIA.md).

# CastiOS 0.25: recuperación temprana del arranque A/B

El kernel candidato deja seleccionada la entrada Estable justo después de
detectar el disco, antes de montar HSFS. Si ambas copias de los metadatos
fallan, arranca en RAM sin escribir en ese volumen y el siguiente arranque
usa Estable. La recuperación anterior sigue disponible en GRUB. Consulta
[actualizaciones](docs/ACTUALIZACIONES.md) y [recuperación](docs/RECUPERACION.md).

# CastiOS 0.24: swap cooperativa para apps AX05

Las apps AX05 pueden reservar una página de datos de 4 KiB, escribirla en
una zona reservada del disco y recuperar la RAM con las syscalls 15..17.
La syscall 18 duerme procesos `bg` por un número de ticks. El código y
la pila siguen residentes. Consulta [swap y sus límites](docs/SWAP.md).

# CastiOS 0.23: base del teclado USB HID

`castctl usbscan` detecta teclados HID boot de alta velocidad en EHCI y
`castctl usbkbd` muestra sus interfaces. El decodificador de informes boot
ya tiene pruebas, pero la recepción periódica de teclas USB y su conexión
a la shell aún están pendientes. Consulta [estado y límites](docs/USB_TECLADO.md).

# CastiOS 0.22: Speed aislado y mejor uso de memoria y disco

`castctl speed RUTA.sp` ahora ejecuta el intérprete en CPL3 con espacio de
memoria privado. Texto, teclado y dibujo pasan por syscalls validadas; el
cargador, el sistema de archivos y los drivers continúan en servicios
privilegiados. El historial de la terminal reserva páginas al llenarse y
la vista de scroll solo se reserva al usarla. HSFS reutiliza huecos de
archivos grandes borrados al importar de FAT32. La configuración completa
se ha probado con 200 MiB de RAM; el modo básico con 32 MiB no dispone
del servicio C ni de Speed. Speed (retirado) ·
[HSFS grande](docs/HSFS_GRANDES.md) ·
[memoria y límites](docs/AISLAMIENTO_PENDIENTE.md).

# CastiOS 0.21: recuperación, escritura HSFS y syscalls de archivos

El kernel candidato arranca una vez: después de detectar el disco, deja
Estable elegido para el siguiente arranque. Si funciona, ejecuta
`castctl kaccept` **durante esa sesión candidata** para conservarlo. HSFS
escribe cada espejo de metadatos con vaciado antes de la cabecera y conserva
la otra copia válida hasta completar el cambio. Las apps AX05 aisladas ya
pueden abrir, leer y cerrar archivos de la raíz; también escribir hasta
256 bytes en archivos de texto existentes de un solo registro. Consulta
[actualizaciones](docs/ACTUALIZACIONES.md), [HSFS](docs/HSFS5.md) y
[syscalls](docs/SYSCALLS.md) para límites y errores.

# CastiOS 0.20: actualizar el kernel desde un archivo IMG

En la imagen HDD, `castctl kbuild` genera `/kernel.img` a partir del árbol
NASM editable. También puedes importar un `.img` compatible a HSFS. Con
`castctl kapply kernel.img` se valida, se escribe en una ranura distinta y
se verifica leyendo el disco; `castctl kstatus` y `castctl krollback`
controlan qué ranura arrancará. GRUB conserva siempre la entrada Estable.
Consulta [docs/ACTUALIZACIONES.md](docs/ACTUALIZACIONES.md).

# CastiOS 0.19: construir un kernel candidato desde CastiOS

La imagen HDD trae fuentes NASM en `/src` y dependencias precompiladas en
`/build`. Edita un modulo con `nano`, ejecuta `castctl kbuild` y quedara
`/kernel.img` sin tocar el arranque. Como alternativa externa usa
`python3 tools/apply_kernel_candidate.py VIEJO.img NUEVO.img` en el anfitrion:
valida el binario, crea un disco distinto y lo prueba arrancando en QEMU.
Mantén el disco viejo como recuperacion. Detalles y limites en
[docs/RECOMPILAR_KERNEL.md](docs/RECOMPILAR_KERNEL.md).

# CastiOS 0.18: primeras syscalls AX05

Los programas aislados en CPL3 pueden consultar PID y ticks y escribir
texto desde sus propias paginas con `int 0x80`. Los punteros se comprueban
y los errores vuelven en EAX. El ensamblador `castctl asm` admite
`mov ebx,numero`, `mov ecx,numero` e `int 0x80` para crear apps desde
CastiOS. Consulta [docs/SYSCALLS.md](docs/SYSCALLS.md) para ABI y limites.

# CastiOS 0.17: configuración interna persistente

`castctl kset` modifica color y prompt desde CastiOS y guarda
`/system.cfg` en HSFS. También puede editarse con `nano` y aplicarse
con `castctl kreload`; el arranque valida y recupera la configuración.
Consulta [docs/CONFIGURACION_INTERNA.md](docs/CONFIGURACION_INTERNA.md).

# CastiOS 0.16: shell estilo Unix

Los comandos visibles y `help` usan nombres familiares de Unix; `castctl`
agrupa funciones propias de CastiOS. `cp` copia archivos HSFS locales
pequeños además de importar desde FAT32; `mv` mueve archivos HSFS.
Consulta [docs/SHELL_UNIX.md](docs/SHELL_UNIX.md) para la lista y los límites.

# CastiOS 0.15: procesos en segundo plano

`bg A.app` inicia un AX05 aislado y devuelve inmediatamente la shell.
`ps` muestra las tareas; `waitbg` espera a que terminen y libera sus
páginas. Admite hasta cuatro tareas por grupo. Mientras haya tareas de fondo,
`run` y `run2` esperan a `waitbg` para mantener separados los dos modos.
La IRQ del reloj reparte tiempo entre la shell y los procesos. Todavía no
hay E/S de archivos desde CPL3, ni aislamiento de Speed o los drivers.

# CastiOS 0.14: cuatro procesos y cesión de turno

`run2 A.app B.app [C.app D.app]` ejecuta de dos a cuatro procesos
AX05 aislados. La llamada `int 0x80` con EAX=2 cede el turno; un
fallo de una tarea deja seguir a las otras. La shell espera a todas.

# CastiOS 0.13: dos procesos y planificador

`run2 A.app B.app` ejecuta dos AX05 en CPL3 con turnos preventivos por
IRQ0 del PIT, CR3 y pila de kernel independientes. Espera a que terminen los
dos; no hay todavía tareas de fondo. La prueba de QEMU comprueba cambios de
contexto y resultados diferentes. Consulta
[docs/AISLAMIENTO_PENDIENTE.md](docs/AISLAMIENTO_PENDIENTE.md).

# CastiOS 0.12: primer proceso de usuario

Los binarios AX05 ejecutados con `run` usan CPL3, tablas de páginas privadas,
pila de usuario con guardia y salida por `int 0x80`. Es un proceso cada vez;
Speed, NASM y controladores siguen en CPL0. Detalles y limitaciones en
[docs/AISLAMIENTO_PENDIENTE.md](docs/AISLAMIENTO_PENDIENTE.md).

# CastiOS 0.11: RMFS + HSFS grandes

RMFS temporal está en `/ram`. HSFS persistente está en el disco y permite importar archivos de hasta 100 MiB con `cp /mnt/ORIGEN /destino`; copia archivos grandes en bloques de 1,44 MiB y admite dos transferencias intercaladas. Consulta [docs/HSFS_GRANDES.md](docs/HSFS_GRANDES.md). Requiere disco suficiente y 200 MiB de RAM desde 0.22.

# CastiOS 0.10

Nueva identidad sobre hermOS: el disco HSFS5 existente se conserva y el arranque, prompt, API y fuentes ahora se denominan CastiOS. La ejecución de Speed sigue interpretada dentro del kernel; USB y kernel no tienen aislamiento CPL3; consulta [docs/AISLAMIENTO_PENDIENTE.md](docs/AISLAMIENTO_PENDIENTE.md). El flujo `tools/update_kernel.py` recompila desde un anfitrión con la VM apagada y avisa antes del siguiente arranque.

# Speed gráfico experimental

Speed permite rectángulos, texto, variables, funciones y eventos de teclado; consulta la documentacion historica de Speed.

# CastiOS 0.9 — HSFS5 y rutas Unix

HSFS5 mantiene 480 bloques de 8 KiB para archivos normales y una region de datos contigua en disco para archivos grandes importados con cp (hasta 100 MiB por archivo). Mantiene dos copias del volumen separadas 4 MiB. Usa rutas absolutas o relativas (`/docs/nota.txt`, `docs/nota.txt`, `..`, `.`), `pwd`, `cd` y `ls /ruta`. Los nombres siguen limitados a 31 caracteres ASCII y no hay permisos Unix ni enlaces simbólicos. El disco sigue usando direccionamiento LBA28 hasta 128 GiB por unidad; el volumen HSFS no ocupa automáticamente todo el disco.

Para actualizar una imagen anterior, usa `python3 tools/install_disk.py NUEVO.img --data ANTERIOR.img`; crea una imagen nueva de 32 MiB y migra los datos ASFS anteriores. Haz copia de seguridad antes de probarla en un disco físico.

# Shell simple optimizada

Prompt CastiOS>, fuente bitmap, alias DIR/TYPE/CLS/COPY/VER y 256 lineas de historial con PgUp/PgDn. Al escribir se vuelve abajo. Consulta [docs/SHELL_OPTIMIZADA.md](docs/SHELL_OPTIMIZADA.md).

# Fuentes TTF, montajes FAT32 y USB 2.0

Esta entrega permite cargar TTF en la terminal, montar FAT32 de solo lectura y leer almacenamiento USB 2.0 EHCI. Consulta [docs/TTF_FAT32_USB.md](docs/TTF_FAT32_USB.md) para comandos, limites y pruebas.

# Terminal framebuffer

Esta entrega dibuja la terminal y nano en un framebuffer RGB32. Ejecuta console para ver el modo. Consulta [docs/CONSOLA_FRAMEBUFFER.md](docs/CONSOLA_FRAMEBUFFER.md).

# Soporte SATA/AHCI

Esta revisión incorpora un controlador AHCI con DMA. Consulta [docs/AHCI.md](docs/AHCI.md).

# Mejora de almacenamiento ATA PIO

Esta entrega incluye detección hda–hdd y mejoras de integridad y diagnóstico.
Consulta [docs/ATA_MEJORADO.md](docs/ATA_MEJORADO.md) para uso, pruebas y límites.

# CastiOS 0.8 — NASM 3.02 y ASFS4

Kernel x86 de 32 bits en NASM, arranque BIOS/GRUB, discos IDE, editor y drivers.
Esta version ejecuta NASM real dentro del sistema, a partir de los fuentes
aportados. No requiere un kernel Linux en la maquina virtual.

## Arrancar
Descomprime todo el ZIP y entra en `CastiOS`:
```sh
bash run.sh
# O arranca el disco ya instalado, sin CD:
bash run-hdd.sh
```
Se usan 200 MiB para NASM desde 0.22. El sistema base puede arrancar con 32 MiB;
en ese caso el comando NASM informa de que no esta disponible.
Comando directo usando los archivos descargados por separado:
```sh
qemu-system-i386 -m 256 -cdrom CastiOS.iso -drive file=CastiOS-hdd.img,format=raw,if=ide -boot d
```
`-boot c` sin `-cdrom` arranca solo desde el disco. La ISO arranca tambien sin
disco, pero los archivos de esa sesion se quedan en RAM.

## NASM dentro del sistema
```text
nasm -v
nasm -f bin demo.asm -o demo.bin
nasm -f bin app.asm -o app.ax
run app.ax
```
El ultimo comando devuelve `EAX=42`. `app.asm` contiene una macro y la cabecera
AX05 que exige el ejecutor. Tambien funcionan includes, etiquetas y generacion
de objetos ELF32; un objeto ELF no es automaticamente un programa ejecutable.
Puedes crear fuentes con `nano nombre.asm` (Ctrl-O guarda; Ctrl-X sale).

NASM opera sobre una copia de ASFS. Si termina con error, se descartan todas
sus escrituras. Si termina correctamente, se valida la copia y se guarda en
las dos ubicaciones del disco. Asi, un error no trunca un binario existente.
Admite hasta 15 argumentos separados por espacios; no hay comillas en la shell.

## ASFS4
Cada archivo puede encadenar bloques de 8000 bytes. Hay 256 bloques compartidos
entre archivos, carpetas y continuaciones: el limite teorico de un solo archivo
con el volumen vacio es 2 048 000 bytes. Los demas archivos reducen ese espacio.
El volumen conserva su tamano de 2 097 664 bytes y las posiciones de ASFS3.

El montaje valida propietarios, ciclos, bloques compartidos o huerfanos,
longitudes, nombres duplicados y padres. Se mantienen checksum, generacion y
copia secundaria. Se escribe primero la copia secundaria y la cabecera al final.
Cada guardado sigue reescribiendo el volumen completo; no hay journal.

`ls`, `cat`, `mkdir`, `cd`, `pwd`, `rm` y las rutas `/ . ..` siguen disponibles.
`rm` y el truncado liberan los bloques de continuacion. El editor nano, append,
MiniDRV y el ensamblador reducido `asm` conservan su limite de 8000 bytes;
NASM puede leer y escribir archivos mayores. `run` mantiene la validacion AX05
y el subconjunto de instrucciones anterior, con hasta 4000 bytes de codigo.

## Importar, exportar y migrar desde Linux
Apaga la VM antes de trabajar con sus imagenes. Estas herramientas crean
destinos nuevos y rechazan sobreescribir imagenes existentes:
```sh
python3 tools/asfs.py build/asfs4.img ls
python3 tools/asfs.py build/asfs4.img check
python3 tools/asfs.py build/asfs4.img put programa.asm programa.asm nuevo.img
python3 tools/asfs.py nuevo.img get programa.asm exportado.asm
python3 tools/install_disk.py disco-migrado.img --data volumen-anterior.img
```
`put --binary` importa datos binarios. La carpeta de destino debe existir.
El importador migra ASFS1, ASFS2 y ASFS3 y puede recuperar la copia secundaria
aunque la firma primaria este destruida. El kernel monta ASFS3 y lo convierte
en ASFS4 en memoria; el siguiente guardado publica el formato nuevo. Para
mantener un disco antiguo intacto, migralo a otra imagen con la herramienta.
Las versiones anteriores del kernel no montan ASFS4.

## Instalacion y drivers
`bash run-install.sh` prepara un disco virtual nuevo. Dentro: `disks`,
`install hda` y confirmar `FORMAT hda`. Se formatea el destino elegido y se
instala GRUB con el modulo NASM; despues puede arrancar sin la ISO.
Las imagenes incluidas tienen 32 MiB. Solo BIOS e IDE de sectores de 512 bytes;
no hay UEFI, AHCI ni NVMe. `drvnew`, `drvload` y `drvunload` conservan MiniDRV;
consulta `docs/DRIVERS.md` y `docs/ESTADO_NASM.md` para los limites de desarrollo.

## Reconstruir y comprobar
Herramientas Linux: NASM, GCC con destino i386, binutils, Python 3, GRUB BIOS,
xorriso y QEMU. En Fedora los ejecutables GRUB pueden llamarse `grub2-*`;
usa equivalentes o enlaces en tu PATH para `grub-mkimage` y `grub-file`.
```sh
bash build.sh
make test
```
Se incluye `build/nasm32` y el ZIP original en `vendor/` con su licencia BSD.
Para reconstruir NASM: `bash tools/build_nasm32.sh`; requiere ademas libc
estatica i386, GCC multilib, autoconf, automake, make y Perl. El adaptador esta
verificado con la compilacion incluida de glibc 2.41: otra libc puede necesitar
otras llamadas y debe pasar las pruebas antes de sustituirla.

NASM se ejecuta como herramienta de confianza en ring 0. No hay aislamiento de
procesos ni compatibilidad general con aplicaciones Linux. El kernel sigue
principalmente en NASM; el adaptador de ABI y la validacion compartida estan en
C. Todavia no existe una cadena completa para reconstruir e instalar todo el
sistema desde dentro: faltan el compilador C, el enlazador y un actualizador de
arranque con version de rescate.


## HSFS 6.1: carpetas y archivos grandes (x64 experimental)

Esta entrega incorpora HSFS6.1, un formato retrocompatible para leer volúmenes
HSFS6 antiguos, con carpetas anidadas, rutas absolutas/relativas, escritura
pequeña en subcarpetas y lectura parcial por offset de 64 bits. La herramienta
del host importa/exporta archivos en streaming (bloques de 1 MiB) y reserva
las extents de ambas generaciones válidas para proteger la recuperación.

**Compilación:** `make` reconstruye las ISOs i386 y x64. Después:
`make image-hsfs61` y `make run-x64-hsfs61` para probar con un disco nuevo.
`make test-hsfs61` ejecuta pruebas sin QEMU. Consulta
[`docs/HSFS61.md`](docs/HSFS61.md) para comandos, limitaciones y pruebas.
**No se convierte ningún disco existente de manera automática.**
