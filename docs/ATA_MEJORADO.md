> Documento de la revisión ATA anterior. El soporte AHCI añadido después se describe en AHCI.md.

# CastiOS 0.8 — mejora ATA PIO, revisión 1

## Qué cambia

El controlador está en src/drivers/ata_pio.asm y se integra estáticamente en
el kernel. Conserva la ABI de bloques y el formato ASFS4.

- Examina los dos canales IDE clásicos y sus posiciones master/slave:
  hda=0x1f0/master, hdb=0x1f0/slave,
  hdc=0x170/master, hdd=0x170/slave.
- Espera después de seleccionar y emitir comandos; todas las esperas de sondeo
  tienen un límite de iteraciones. No son plazos calibrados en milisegundos.
- Distingue ausente, ATA utilizable, ATAPI, timeout, formato de sector/LBA
  incompatible y error de IDENTIFY.
- Lee el modelo, valida LBA y sectores lógicos de 512 bytes. 512e es compatible;
  4Kn se rechaza. No se convierten sectores ni se intenta formatearlos.
- Usa la capacidad IDENTIFY LBA48 cuando está declarada válida para calcular
  una ventana LBA28 correcta en discos grandes. Los comandos siguen siendo
  LBA28: como máximo 268435456 sectores (128 GiB) accesibles por disco.
- Comprueba el LBA físico también en la ruta de bajo nivel usada por el
  instalador. Rechaza desbordamientos al sumar desplazamientos ASFS.
- Después de una transferencia espera a que BSY y DRQ se desactiven y
  comprueba ERR/DF. El driver usa polling y deshabilita sus IRQ con nIEN.
- FLUSH CACHE selecciona explícitamente la unidad y comprueba terminación.
  Por prudencia, una unidad que no declara FLUSH CACHE válido puede leerse,
  pero el controlador rechaza escribir en ella.
- No reintenta escrituras ni reinicia canales automáticamente tras un error.
- Si el disco preferido no contiene ASFS válido, intenta las otras unidades
  ATA en orden. Se prefiere siempre el disco solicitado si su volumen es válido.
  Detectar un disco no implica que contenga ASFS ni que sea un destino de instalación.
- El montaje conserva la recuperación entre las dos copias ASFS. No escribe
  para buscar un volumen. Si no hay volumen válido, sigue trabajando en RAM.
- disks muestra estado, capacidad accesible, modelo, unidad activa, último
  status/error observado y contador de fallos de E/S. Estos registros son
  globales, no un historial por unidad; algunos rechazos de argumentos se
  producen antes de acceder al hardware.
- disks también informa de controladores PCI IDE, SATA/AHCI y NVM.
  Es inventario, no soporte de esos protocolos.
- GRUB acepta disk=hda, hdb, hdc o hdd.
  install y tools/install_disk.py aceptan las cuatro posiciones.

## Uso

Ejecuta disks para ver qué se ha detectado. El sufijo [activo] identifica la
unidad elegida para ASFS. Los números son sectores accesibles de 512 bytes,
no la capacidad total de un disco grande.

Para crear un disco de prueba nuevo desde Linux:
    bash build.sh
    python3 tools/install_disk.py nuevo.img --target hdc

Al conectar nuevo.img como secondary master, puede arrancar desde HDD.
La ISO Live sigue siendo la vía para instalar desde dentro:
    install hdc
La confirmación será FORMAT hdc. Ese comando borra el destino elegido.

El cambio de unidad no es una operación de shell para volúmenes montados.
No se debe llamar a select_disk desde aplicaciones ni modificar fs_io_bias.

## Límites reales

Esta revisión NO implementa AHCI, NVMe, USB Mass Storage, VirtIO, controladores
IDE PCI en modo nativo con BAR alternativos, DMA, LBA48 de transferencia,
particiones GPT/MBR arbitrarias, múltiples montajes ni hotplug.
SATA solo es accesible si el controlador presenta una interfaz IDE compatible
con los puertos clásicos. Una VM que exponga AHCI requiere otro controlador;
cambiar la extensión del archivo de disco no cambia su interfaz.

El sistema sigue esperando ASFS al inicio del disco o en LBA 32768 y su espejo.
Esta mejora no convierte ASFS4 en un sistema de archivos de tamaño ilimitado.
Los fallos y los timeouts se notifican; no se garantiza recuperación de un
dispositivo físico averiado ni de su firmware. Se ha probado en emulación
QEMU; falta validación en hardware físico.

## Pruebas reproducibles

Dependencias: las originales de build.sh, QEMU x86 y Python 3.
Usa QEMU_EXTRA_ARGS="-m 256" para los módulos de NASM.

    bash build.sh
    QEMU_EXTRA_ARGS="-m 256" python3 tools/test_ata_detection.py
    QEMU_EXTRA_ARGS="-m 256" python3 tools/test_ata_errors.py
    QEMU_EXTRA_ARGS="-m 256" python3 tools/test_ata_secondary_install.py
    QEMU_EXTRA_ARGS="-m 256" python3 tools/test_08.py
    QEMU_EXTRA_ARGS="-m 256" python3 tools/test_08_migration.py
    QEMU_EXTRA_ARGS="-m 256" python3 tools/test_08_regression.py

Las pruebas usan imágenes temporales. La de disco grande usa un archivo
disperso de 140 GiB; requiere un filesystem con soporte de archivos dispersos.

QEMU ide-hd no admite esta configuración de sectores lógicos 4Kn. La
guardia de rechazo está implementada y revisada, pero esa prueba se marca
SKIP: no se afirma validación de 4Kn físico ni una prueba emulada que no
pudo ejecutarse.

Los tests históricos test_release.py/test_install.py son de la versión 0.5:
esperan ASFS2 y no son la batería vigente para ASFS4. No se han presentado
como superados. Consulte ATA_VALIDACION.txt para los resultados de esta revisión.

Referencias de protocolo: campos IDENTIFY y comandos ATA documentados en
manuales de fabricante, por ejemplo:
https://www.seagate.com/files/www-content/product-content/skyhawk/en-us/docs/100818528c.pdf
