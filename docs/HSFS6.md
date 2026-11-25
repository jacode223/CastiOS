# HSFS6 experimental en CastiOS x86-64

HSFS6 es un formato nuevo incompatible en disco con HSFS5. La shell x64 usa
`mount`, `ls`, `cat nombre`, `stat nombre` y `echo texto > nombre` para HSFS6;
`mount6`, `ls6`, `cat6`, `stat6` y `write6` son alias. Esta versión usa un único directorio
raíz de hasta 128 archivos con nombres ASCII de hasta 63 caracteres. El tamaño
de archivo, sector inicial, capacidad del volumen y generación son enteros de
64 bits. No se migran ni formatean volúmenes HSFS5 automáticamente.

El lector x64 utiliza IDE primario maestro y el controlador ATA PIO LBA28 de
CastiOS. Por tanto, aunque el formato almacena sectores de 64 bits, **el límite
efectivo actual es 2^28 sectores de 512 bytes, es decir, 128 GiB**, y el acceso
puede ser menor según la capacidad real del disco. No hay LBA48, AHCI ni USB
en esta ruta. No hay directorios anidados ni escritura de archivos grandes desde CastiOS todavía.
`stat6` muestra longitud y posición aunque el contenido exceda LBA28; `cat6`
rechaza cualquier lectura que exceda ese límite o el tamaño del volumen.

Para crear una imagen NUEVA desde el host, situándose en la carpeta CastiOS:

```sh
python3 tools/hsfs6.py mkfs hsfs6.img --size-mib 1024
python3 tools/hsfs6.py put hsfs6.img hola.txt ./hola.txt
python3 tools/hsfs6.py ls hsfs6.img
```

El formateador falla si el archivo destino ya existe. `put` escribe en bloques
nuevos, sincroniza datos, escribe la tabla alternativa, sincroniza, publica su
cabecera y sincroniza. La cabecera y la tabla tienen sumas independientes; el
montaje escoge la generación válida mayor. La herramienta no modifica HSFS5.
En la consola x64, `echo texto > nombre.txt` crea o reemplaza un archivo de
texto en la raíz. Se limita a una línea de entrada de hasta 62 caracteres en
total; no es un editor ni una copia de archivos grandes. El kernel comprueba
IDENTIFY, capacidad y disponibilidad de FLUSH, valida la tabla, escribe datos
en un sector nuevo y sincroniza; publica la tabla alternativa y luego la
cabecera, sincronizando en cada etapa. Si falla la E/S desactiva el montaje y
debe ejecutarse `mount6` de nuevo. La recuperación ante corte depende de que
el hardware respete FLUSH y de que quede una copia intacta.
El contenido de archivos no tiene checksum, la suma es aditiva (no
criptográfica), y los resultados no sustituyen la prueba en hardware físico.
La escritura desde el host exige exclusividad: apaga la VM antes de usarla.

Diseño v1 (sectores de 512 bytes): cabeceras en LBA 8 y 9, tablas de 128
registros de 128 bytes en LBA 16 y 48, respectivamente, datos desde LBA 80.
Cada registro contiene nombre[64], tipo/UID/GID/modo de 32 bits y longitud y
LBA inicial de 64 bits. La shell ejecuta como privilegiada. Para tareas CPL3,
la syscall 6 lee hasta 512 bytes a la página de datos y comprueba permisos
UID/GID/modo; la syscall 7 escribe texto corto y requiere UID 0. El nombre y
texto deben residir en la página de código privada; no hay descriptores de
archivo generales. La herramienta host reserva datos al final sin reclamar huecos.

`tools/test_hsfs6.py` crea un volumen sparse de 6 GiB, escribe un archivo más
allá del offset de 4 GiB y otro de 101 MiB, y los consulta desde QEMU. Crea,
reemplaza y remonta un archivo desde el kernel. También corrompe metadatos en
la imagen para probar recuperación de una generación anterior. No simula
todos los posibles cortes de energía ni comprueba hardware físico.
