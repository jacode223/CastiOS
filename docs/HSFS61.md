# CastiOS HSFS 6.1 (x86-64 experimental)

## Qué mejora

HSFS6.1 añade **directorios anidados persistentes** a HSFS6 y mantiene los
campos de tamaño y LBA de **64 bits**. Permite nombres repetidos en carpetas
diferentes y rutas absolutas/relativas. En el host, `put` y `get` copian datos
en **bloques de 1 MiB**, en vez de cargar archivos grandes en memoria;
`get --offset/--length` extrae fragmentos sin leer el fichero entero.
En el kernel x64, `read6` muestra 1..512 bytes a partir de un offset de 64
bits, útil para inspeccionar archivos grandes sin inundar la consola.
La syscall 6 conserva los offsets de 64 bits y sus lecturas fragmentadas.
`cp origen destino` copia hasta 500 MiB en sectores de 512 bytes, sin reservar
memoria proporcional al archivo. Se necesita espacio contiguo suficiente en
el volumen para la copia completa; se escribe con copia en nueva ubicación y
se confirma la tabla tras FLUSH. El controlador actual es IDE PIO, por lo que
una copia grande puede tardar bastante. Si falla, vuelve a montar el volumen.
Se ha comprobado en QEMU la copia completa de un archivo de más de 2 MiB con
comparación byte a byte. Un archivo real de 500 MiB se ha importado desde el
host y se ha leído desde el kernel, incluyendo sus últimos bytes. La prueba
de copia completa de 500 MiB no ha terminado dentro del tiempo disponible;
se puede ejecutar con `HSFS_FULL_COPY=1 make test-hsfs61-vm` para verificarla.

No confundir tamaño del archivo con memoria: no se reserva RAM por el tamaño
completo. Se reservan extents contiguos en el volumen. Actualmente **no** hay
extents indirectos, bloques dispersos, desfragmentación ni LBA48. El volumen
mantiene 128 entradas **entre archivos y directorios**. El acceso x64 a datos
se limita a IDE primario ATA PIO LBA28 (128 GiB), aunque el formato registre
tamaños y direcciones en 64 bits. AHCI sigue siendo de solo lectura en esta
ruta. Las escrituras de texto dentro de CastiOS siguen limitadas a un sector
por operación; los archivos grandes se pueden copiar con `cp` o importar desde
el host con la VM apagada. El uso de `cat` sobre binarios/grandes puede inundar la
terminal, por eso se incorpora `read6`.

## Formato en disco

- Sector: 512 bytes. Cabeceras espejadas: LBA 8 y 9.
- Tablas espejadas: LBA 16 y 48, 128 registros de 128 bytes cada una.
- Datos: a partir de LBA 80.
- Magic: `HSFS6\0\0\0`, versión mayor 6 en offset 8.
- **Minor version** u32 en cabecera offset 48: `0` HSFS6 antiguo, `1` HSFS6.1.
- **Marca alta de asignación** u64 en cabecera offset 56, para la escritura
  append-only del kernel. Valores 0 de medios antiguos también se admiten.
- Cada entrada: nombre NUL-terminado de hasta 63 ASCII `[A-Za-z0-9_.-]` en
  bytes 0..63, tipo u32 en 64 (`1` archivo, `2` directorio), UID/GID/modo
  u32 en 68/72/76, tamaño u64 en 80, LBA de inicio u64 en 88, **padre u32**
  en offset 96. `0` representa la raíz; `índice + 1` representa un directorio
  existente en la tabla.
- Los directorios son registros con tamaño `0` y LBA `80` (sin extents propios).
- Se rechazan nombres duplicados bajo el mismo padre, padres inválidos,
  referencias cíclicas, archivos solapados y rangos fuera del volumen.

Los metadatos se publican mediante dos generaciones: primero datos y FLUSH,
después tabla alternativa y FLUSH, finalmente cabecera alternativa y FLUSH.
El host evita reasignar datos aún referenciados por **cualquiera de las dos
copias válidas**. El kernel escribe siempre en el extremo superior reservado
(append-only). Ninguna de estas protecciones equivale a un journal completo.

**Compatibilidad:** el kernel HSFS6.1 puede montar y escribir archivos en raíz
en un volumen HSFS6 minor=0, sin añadirle carpetas. Crear un volumen 6.1 es
una operación **nueva**: `mkfs` se niega a sobrescribir imágenes existentes;
no se migra HSFS5 ni HSFS6 antiguo automáticamente. Las versiones antiguas
del kernel no deben utilizarse para montar HSFS6.1.

## Preparar el proyecto (Linux)

Instala NASM, GCC con soporte `-m32`, binutils, Python 3, GRUB para BIOS,
`xorriso`, `make`; para ejecutar también QEMU. Desde la carpeta `CastiOS/`:

```bash
make                   # i386 + ISO experimental x86-64
make test-hsfs61       # pruebas del formato y su herramienta, sin QEMU
make image-hsfs61      # disco HSFS6.1 de muestra; sin sobrescribir si existe
make run-x64-hsfs61    # arranca la ISO x64 con ese disco en QEMU
make test-hsfs61-vm    # regresión de rutas y operaciones usando QEMU
```

`make` necesita `grub-file`, `grub-mkimage` y módulos en
`/usr/lib/grub/i386-pc`, además de `xorriso`. `GRUB_DIR` permite modificar
la ruta de módulos. El paso `make` también construye la rama i386 histórica.

## Herramienta del host

```bash
python3 tools/hsfs6.py mkfs disco.img --size-mib 1024
python3 tools/hsfs6.py mkdir disco.img docs
python3 tools/hsfs6.py mkdir disco.img docs/dev
python3 tools/hsfs6.py put disco.img docs/dev/archivo.bin ./archivo.bin
python3 tools/hsfs6.py ls disco.img /
python3 tools/hsfs6.py ls disco.img docs/dev
python3 tools/hsfs6.py stat disco.img docs/dev/archivo.bin
python3 tools/hsfs6.py get disco.img docs/dev/archivo.bin ./salida.bin
python3 tools/hsfs6.py get disco.img docs/dev/archivo.bin ./trozo.bin --offset 1048576 --length 4096
```

El parámetro `--start-lba` de `put` se mantiene para ensayos explícitos y
rechaza solapamientos. Un `get` tampoco sobrescribe ficheros de destino.
`mkfs --legacy` genera HSFS6 minor=0 si se necesita probar compatibilidad.
**Nunca modifiques una imagen montada por QEMU a la vez desde el host.**

## Terminal x64

```text
mount6
ls /
mkdir /docs
mkdir /docs/dev
cd /docs/dev
pwd
write6 nota.txt hola
cat nota.txt
stat nota.txt
read6 nota.txt 0 4
cd ..
ls
cd /
```

También admite `mount`, `ls`, `mkdir`, `cat`, `cd`, `pwd` y
`echo texto > ruta.txt`. Un `write6` solo admite una línea corta de texto;
no hay API de escritura de archivos grandes desde CPL3 ni descriptores
POSIX todavía. La ruta de entrada de la shell está limitada a 62 caracteres.

## Validación y riesgos

`tools/test_hsfs61_unit.py` valida jerarquías, lectura parcial, archivos de
varios MiB, metadatos duplicados/cíclicos, recuperación tras cabecera rota,
compatibilidad con imágenes HSFS6 antiguas y posiciones LBA por encima de
4 GiB. `tools/test_hsfs61_vm.py` prueba los comandos del kernel **solo si**
hay QEMU, GRUB y una ISO reconstruida. El uso en discos físicos requiere
validación adicional; no formatees discos reales con este desarrollo.
