> Nota de version: esta guia describe la entrega historica EHCI. Para el nuevo
> controlador experimental UHCI/xHCI consulta [CastiUSB](CASTIUSB_EXPERIMENTAL.md).

# Fuentes TTF, montajes FAT32 y USB 2.0 — CastiOS 0.8

La entrega es el sistema operativo completo. Incluye los controladores
IDE/AHCI y la terminal framebuffer anteriores. Los nuevos servicios están
en src/extensions y se integran estáticamente en el kernel.

## Uso rápido: disco FAT32

Ejecuta volumes para ver discos y particiones detectados. Por ejemplo,
si FAT32 está en la primera partición de hdb:

    mount hdb1 /mnt/datos
    ls /mnt/datos
    cd /mnt/datos
    pwd
    cat README.TXT
    stat /mnt/datos/README.TXT
    cd /
    umount /mnt/datos

hda..hdd son las entradas lógicas de discos IDE/AHCI existentes. No equivalen
necesariamente a puertos SATA físicos. Montar un volumen externo no cambia
la unidad ASFS activa ni sus desplazamientos: las lecturas crudas restauran
la selección original.

Si el disco contiene FAT32 directamente, sin tabla de particiones, usa
mount hdb /mnt/datos. El sufijo 1 selecciona una partición; no es parte del
nombre de la unidad.

## Uso rápido: pendrive USB

Conecta el dispositivo a la máquina invitada y ejecuta:

    usbscan
    usbinfo
    volumes
    mount usb0p1 /mnt/usb
    ls /mnt/usb
    cat /mnt/usb/README.TXT

usb0p1 selecciona la primera partición del primer USB detectado.
Si el USB no tiene tabla de particiones y FAT32 ocupa todo el dispositivo:

    mount usb0 /mnt/usb

No formatees un USB para comprobar si se detecta. usbinfo informa de
VID/PID, puerto raíz, capacidad y estado. volumes muestra las particiones.

usbscan toma control exclusivo del primer EHCI encontrado y reinicializa
su bus. Invalida y desmonta los montajes USB anteriores. Después hay que
montarlos de nuevo. Los índices usb0..usb3 pueden cambiar al retirar un
dispositivo; consulta usbinfo tras cada scan. No hay automontaje.

### VirtualBox

Configura USB 2.0 (EHCI), inicia la ISO nueva y conecta el pendrive al
invitado mediante el menú de dispositivos USB. El host y el invitado deben
haber cedido el dispositivo correctamente. Esta entrega no controla xHCI:
un controlador virtual USB 3.0 no sustituye a EHCI para este kernel.

Documentación de los ajustes USB:
https://docs.oracle.com/en/virtualization/virtualbox/7.2/user/working-with-vms.html

VirtualBox sigue pendiente de prueba directa; las pruebas realizadas usan
QEMU con USB EHCI y almacenamiento masivo emulado.

## Elegir una TTF

La terminal debe estar en framebuffer; console muestra el modo.
Se recomienda una fuente monoespaciada TrueType de tamaño inferior a 1 MiB.
Copia el archivo TTF al FAT32 desde el anfitrión y ejecuta:

    font /mnt/usb/FONT.TTF

Se lee y rasteriza la TTF dentro de CastiOS. No requiere convertirla en el
anfitrión. Para volver a la fuente inicial:

    font default

La selección es de la sesión actual y no se activa automáticamente al
reiniciar. La cuadrícula sigue siendo 80x25, con celdas de 12x24 píxeles.

También puedes conservar una copia en ASFS:

    cp /mnt/usb/FONT.TTF /mi_fuente.ttf
    cd /
    umount /mnt/usb
    font /mi_fuente.ttf

cp importa desde FAT32 a HSFS (o a /ram para archivos que quepan en RMFS). La importación
se prepara en una copia de ASFS, se valida y solo después se publica y
sincroniza. Un error de espacio o de validación descarta la copia.

TTF y cp requieren 200 MiB de RAM y el módulo NASM de la entrega. Reutilizan
temporalmente la ventana de trabajo reservada de NASM; no hay ejecución
concurrente de esas herramientas. El bitmap resultante se conserva aparte.

## Qué se puede leer y montar

- Hasta cuatro montajes FAT32 simultáneos, todos de solo lectura.
- Discos IDE/AHCI y hasta cuatro dispositivos USB compatibles.
- FAT32 directo, particiones MBR primarias 1..4 y GPT 1..128.
- Validación CRC del encabezado GPT y de su matriz de particiones.
- Sectores lógicos de 512 bytes y tamaños de cluster FAT32 de hasta 64 KiB.
- Directorios, archivos, nombres cortos 8.3 y nombres largos ASCII.
- Nombres FAT sin distinción entre mayúsculas y minúsculas.
- Rutas absolutas, cd, pwd, . y .. dentro de /mnt.
- cat para texto, stat para metadatos y cp hacia ASFS.
- mount sin argumentos lista los montajes; umount los retira.

No hay escritura FAT32, formateo externo, particiones MBR extendidas,
FAT12/FAT16, exFAT, NTFS o ext4. Los otros volúmenes ASFS no se montan como
volúmenes externos en esta revisión. /mnt queda reservado al espacio de
montajes.

Los nombres largos no ASCII se presentan mediante su alias 8.3. Para
rutas con espacios, cat, stat y font aceptan todo el resto de la línea como
ruta. cp separa sus dos argumentos por espacios: usa el alias 8.3 cuando
el nombre de origen los contenga. No se añade una sintaxis de comillas.

font se limita a 1 MiB por archivo; cp admite hasta 100 MiB por archivo,
en bloques de 1,44 MiB cuando supera 1 MiB. cat lee archivos grandes
por sectores; stat informa del tamaño. Las cadenas de directorios/archivos tienen un límite
de 4096 clusters visitados, con detección de bucles. Geometrías inválidas,
cadenas truncadas y errores de E/S devuelven un error.

## Crear una imagen FAT32 de demostración

Desde el anfitrión, con mkfs.fat y mtools instalados:

    python3 tools/make_fat_demo.py demo.img --font /ruta/fuente.ttf

Crea un archivo nuevo de 64 MiB con README.TXT y FONT.TTF; rechaza destinos
existentes y rutas de dispositivos. No modifica la TTF de origen.
La imagen es FAT32 directa: al exponerla como USB se monta con usb0,
sin p1. No es una imagen de arranque del sistema operativo.

## Alcance USB

- Primer controlador PCI EHCI, USB 2.0 high-speed, puertos raíz.
- Enumeración estándar, selección de configuración e interfaces MSC.
- Almacenamiento masivo SCSI transparent / Bulk-Only Transport, LUN 0.
- READ CAPACITY(10) y READ(10), sectores de 512 bytes, capacidad de 32 bits.
- Transferencias control/bulk síncronas por sondeo, sin IRQ USB.
- Descriptores DMA de 32/64 bits con direcciones físicas inferiores a 4 GiB.
- Retirada detectada al leer y rescan explícito para volver a enumerar.

No hay hubs, xHCI, OHCI/UHCI, UAS, varios LUN, discos USB 4Kn, teclado HID,
ratón USB, recuperación automática de stalls ni soporte de todo firmware.
El controlador reclama EHCI: no implementa otros dispositivos conectados
a ese controlador. Los teclados PS/2 emulados siguen usando su driver.

## Alcance tipográfico

El parser acepta fuentes TrueType con contornos glyf, loca, head, hhea,
hmtx, maxp y cmap formato 4 o 12. Rasteriza glifos simples ASCII 32..126,
con segmentos y curvas cuadráticas. No ejecuta bytecode de fuentes.

No es un motor OpenType completo: no hay hinting, antialiasing, kerning,
ligaduras, fuentes variables, colecciones TTC, contornos CFF ni entrada
Unicode. Los glifos compuestos/no disponibles conservan la fuente bitmap
de respaldo y se indica la cantidad. Una fuente sin glifos ASCII utilizables
se rechaza. Las proporcionales se ajustan a la celda fija; para programar
es preferible una monoespaciada.

Se validan rangos y longitudes antes de leer tablas y contornos. El cambio
de bitmap es transaccional: una TTF rechazada no cambia la fuente activa.

## Construcción y pruebas

    bash build.sh
    QEMU_EXTRA_ARGS="-m 256" python3 tools/test_external.py
    QEMU_EXTRA_ARGS="-m 256" EXT_MODE=ahci python3 tools/test_external.py
    QEMU_EXTRA_ARGS="-m 256" EXT_MODE=gpt python3 tools/test_external.py
    QEMU_EXTRA_ARGS="-m 256" EXT_MODE=usb python3 tools/test_external.py
    QEMU_EXTRA_ARGS="-m 256" python3 tools/test_usb_lifecycle.py
    QEMU_EXTRA_ARGS="-m 256" python3 tools/test_fat32_errors.py
    QEMU_EXTRA_ARGS="-m 256" python3 tools/test_08.py

Las pruebas FAT requieren mkfs.fat y mtools en el anfitrión. Se crean
imágenes temporales; no se usan dispositivos físicos. TEST_TTF permite
elegir una fuente del anfitrión para las pruebas. No se distribuyen esas
TTF con el sistema.

El parser exacto de TTF también se prueba en el anfitrión:

    gcc -O1 -g -fsanitize=address,undefined -fno-omit-frame-pointer tools/test_truetype_host.c -o /tmp/test_ttf
    ASAN_OPTIONS=detect_leaks=0 UBSAN_OPTIONS=halt_on_error=1 /tmp/test_ttf /ruta/fuente.ttf

Esta prueba acotada de mutaciones no equivale a demostrar que todo archivo
malformado sea seguro. La validación se ha realizado en QEMU y con los
sanitizers indicados, no en hardware físico.

Consulta EXTERNOS_VALIDACION.txt para resultados y hashes de esta entrega.

## Referencias de programación

https://www.intel.com/content/dam/www/public/us/en/documents/technical-specifications/ehci-specification-for-usb.pdf
https://www.usb.org/sites/default/files/usbmassbulk_10.pdf
https://learn.microsoft.com/en-us/typography/opentype/spec/otff
https://learn.microsoft.com/en-us/typography/opentype/otspec190/cmap
