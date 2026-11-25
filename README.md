# CastiOS

**Sistema operativo experimental para PC, con kernel propio, shell, escritorio gráfico y herramientas de programación integradas.**

CastiOS está desarrollado principalmente en ensamblador NASM y C. La versión actual se centra en **x86 de 32 bits (i386)** y permite ejecutar aplicaciones propias, trabajar con archivos y crear programas desde el sistema.

> Proyecto en desarrollo activo. La compatibilidad depende del hardware. Utiliza una máquina virtual o un disco de pruebas.
>
> **El comando `install` borra el disco elegido, incluidas sus particiones y datos.**

## Características

### Sistema

- Arranque BIOS mediante GRUB y Multiboot.
- ISO live y posibilidad de instalación en disco.
- Shell con comandos de estilo Unix.
- Terminal con framebuffer, historial y desplazamiento.
- Editor de texto `nano`.
- Configuración editable mediante `/system.cfg`.

### Escritorio

- Escritorio integrado con ventanas, menú y barra de tareas.
- Movimiento, cambio de tamaño, minimización y maximización de ventanas.
- Explorador básico de archivos, vista previa de texto e información de procesos.
- Escritorio experimental escrito en **Castic**, con código editable dentro del sistema.
- Manejo mediante teclado y soporte de ratón compatible.

### Almacenamiento

- Controladores ATA/IDE clásico, IDE PCI nativo y SATA/AHCI.
- Soporte experimental para VIA VT6421.
- Detección de modelos, capacidad accesible y errores mediante `disks`.
- Sistema de archivos **HSFS5** en la versión i386.
- Carpetas, subcarpetas y rutas absolutas y relativas.
- Almacenamiento temporal **RMFS** en `/ram`.
- Montaje FAT32 de solo lectura.
- Importación de archivos grandes desde FAT32, hasta **100 MiB**, con las restricciones del perfil de memoria.
- Controladores experimentales de almacenamiento USB EHCI, UHCI y xHCI.

### Procesos y memoria

- Aplicaciones AX05 ejecutadas en **CPL3**.
- Memoria privada por proceso y protección del código.
- Multitarea preventiva con hasta **cuatro tareas simultáneas**.
- Procesos en segundo plano mediante `bg`.
- Gestión de tareas con `ps`, `kill` y `wait`.
- Asignación limitada de páginas por demanda.
- Swap cooperativa de **100 KiB**.

### Desarrollo dentro del sistema

- NASM integrado.
- Compilador del lenguaje **Castic**.
- Variables, operaciones aritméticas, condiciones y bucles.
- Funciones sencillas y bibliotecas en `/lib`.
- Syscalls para consola, archivos, gráficos, teclado y otras funciones.
- Guías de uso disponibles en `/docs`.

### Actualizaciones

- Actualización del kernel desde una ISO live en instalaciones compatibles.
- Ranuras de kernel estable y candidato.
- Validación de la imagen antes de seleccionar el nuevo arranque.
- Herramientas para aplicar, aceptar y revertir una actualización.

## Descargar

Las imágenes ISO y los paquetes de fuentes están disponibles en [Releases](https://github.com/jacode223/CastiOS/releases).

Las versiones experimentales se publican como **pre-releases**.

## Compilar

La compilación se realiza desde Linux.

Necesitas:

- `make`
- GCC con soporte de compilación de 32 bits
- Binutils
- NASM
- Python 3
- GRUB con herramientas y módulos para BIOS/i386-pc
- `xorriso`

Para construir la versión i386:

```sh
make i386
```

La imagen resultante se genera en:

```text
build/CastiOS.iso
```

El paquete de fuentes distribuido incluye `build/nasm32`, utilizado para ejecutar NASM dentro de CastiOS. Si falta, consulta `tools/build_nasm32.sh`.

## Probar en QEMU

```sh
qemu-system-i386 \
  -m 256 \
  -boot d \
  -cdrom build/CastiOS.iso
```

Este comando inicia una sesión live sin disco duro virtual. Los archivos creados durante esa sesión se pierden al apagar.

Se han probado funciones básicas con **32 MiB de RAM**. NASM, las fuentes TTF y determinadas operaciones de archivos requieren el perfil completo, de aproximadamente **200 MiB**. Para las pruebas generales se utilizan **256 MiB**.

## Primeros comandos

```text
help
uname
disks
ls /
ls /docs
```

Para consultar la pantalla:

```text
castctl console
```

Para listar dispositivos PCI:

```text
castctl pci
```

Para buscar dispositivos USB:

```text
castctl usbscan
castctl usbinfo
```

## Escritorio en Castic

En una instalación nueva o una sesión live con raíz temporal, compila y ejecuta el escritorio:

```text
castic /desk.cas /desk.app
exec /desk.app
```

| Tecla | Acción |
|---|---|
| `1` | Información |
| `2` | Discos detectados |
| `3` | Ayuda |
| `Q` o `Escape` | Volver a la terminal |

El código principal está en `/desk.cas` y utiliza `/lib/desk.cas`.

Para abrir el escritorio integrado:

```text
desktop
```

## Ejemplo de Castic

```c
int a = 0;

while (a < 5) {
    a += 1;
}

return a;
```

Guarda el programa como `/ejemplo.cas` y ejecuta:

```text
castic /ejemplo.cas /ejemplo.app
exec /ejemplo.app
```

Castic implementa un subconjunto pequeño de construcciones de estilo C. Las variables tienen nombres de una letra y las funciones actuales son sencillas, sin parámetros.

## Estructura del proyecto

| Ruta | Contenido |
|---|---|
| `src/` | Kernel y componentes del sistema |
| `src/drivers/` | Controladores integrados |
| `src/extensions/` | Servicios escritos en C y escritorio integrado |
| `src/console/` | Consola y framebuffer |
| `src/x64/` | Desarrollo experimental de la rama x86-64 |
| `lib/` | Bibliotecas e inclusiones para programas |
| `examples/` | Programas de ejemplo y escritorio Castic |
| `docs/` | Documentación técnica y de uso |
| `docs/on_disk/` | Guías incorporadas al sistema |
| `tools/` | Herramientas de construcción y pruebas |
| `vendor/` | Componentes de terceros y sus licencias |
| `build/` | Archivos generados durante la compilación |

## Pruebas

Con la ISO compilada, QEMU, Python y las dependencias de cada prueba instaladas:

```sh
python3 tools/test_castic_desktop_vm.py
python3 tools/test_castic_graphics_abi.py
python3 tools/test_ata_detection.py
python3 tools/test_ahci.py
python3 tools/test_pci_ide_native_vm.py
```

Las pruebas cubren el escritorio, las llamadas gráficas, la detección de discos y varias rutas de lectura, escritura y persistencia.

La prueba IDE PCI nativa utiliza puertos de E/S emulados y una configuración PCI simulada en una compilación temporal.

## Limitaciones actuales

- Compatibilidad con hardware físico todavía en validación.
- USB y HID experimentales.
- FAT32 y almacenamiento USB de solo lectura.
- Acceso ATA PIO limitado a **128 GiB**.
- Soporte pendiente de exFAT, NVMe y RAID.
- Instalación actual en disco completo.
- Sesión única `root`, con autenticación y cuentas de usuario pendientes.
- Soporte multinúcleo, red, audio y gestión de energía pendientes.
- El inspector PE32 permite analizar ejecutables Windows; su ejecución sigue pendiente.
- Las ramas i386 y x86-64 tienen funciones y sistemas de archivos diferentes.

## Informar de un problema

Abre una [issue](https://github.com/jacode223/CastiOS/issues) e incluye:

- Versión o nombre de la ISO utilizada.
- Modelo del equipo o configuración de la máquina virtual.
- Pasos para reproducir el problema.
- Resultado esperado y resultado observado.
- Mensajes de error o fotografías legibles.
- Para problemas de almacenamiento, salida de `disks` y `castctl pci`.

## Licencia

Consulta el archivo [LICENSE](LICENSE).

Los componentes de terceros conservan sus licencias correspondientes, disponibles junto a sus fuentes.
