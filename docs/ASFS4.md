# Formato ASFS4

Enteros little-endian. El volumen mide 512 + 256 * 8192 = 2 097 664 bytes.
El kernel reserva la primera copia en LBA 32768 en discos GRUB, o LBA 0
en imagenes de datos; la segunda esta 8192 sectores despues de la primera.
Cada sector mide 512 bytes.

| Offset de cabecera | Campo |
| --- | --- |
| 0 | Cuatro bytes `ASF4` |
| 4 | Version DWORD = 4 |
| 8 | Bloques DWORD = 256 |
| 12 | Tamano de bloque DWORD = 8192 |
| 16 | Suma DWORD de todos los bytes posteriores a la cabecera |
| 20 | Generacion DWORD |

Los registros empiezan en offset 512. Un byte cero al principio indica libre.

| Offset de registro | Campo |
| --- | --- |
| 0..31 | Nombre ASCII terminado en cero, hasta 31 caracteres |
| 32 | Padre DWORD; `0xffffffff` representa la raiz |
| 36 | Tipo DWORD: 1 texto, 2 carpeta, 3 binario, 4 continuacion |
| 40 | Longitud DWORD total del archivo o de esta continuacion |
| 44 | Indice DWORD del siguiente registro + 1; cero significa fin |
| 64 | Hasta 8000 bytes de contenido |

Una continuacion usa `0xff` como primer byte y no tiene nombre publico. Su
campo de padre contiene el indice del registro principal propietario. Cada
continuacion, salvo la ultima, contiene exactamente 8000 bytes. Las carpetas
tienen longitud y siguiente iguales a cero. El texto tiene un byte cero tras
los datos de cada registro, fuera de la longitud declarada.

El validador comprueba longitud, cantidad de continuaciones, propietario,
ausencia de ciclos, ausencia de bloques compartidos o huerfanos y arbol de
directorios. Las continuaciones no cuentan como archivos en `ls`, aunque
consumen espacio. La capacidad maxima es compartida; no hay tabla separada
de 256 archivos ademas de los bloques de datos.

Al montar se valida cada copia y se elige la generacion mas alta. Cada guardado
publica primero los datos y despues la cabecera de la copia secundaria, vacia
la cache ATA y repite con la primaria. El checksum es una suma, no CRC ni hash
criptografico, y no proporciona las garantias de un journal.

ASFS3 puede convertirse sin mover registros porque el campo 44 estaba a cero.
La migracion cambia la cabecera despues de validar la estructura antigua.
Las herramientas importan ASFS1/2 a una imagen nueva. Usa `body()` y `put()`
de `tools/fs_format.py` para trabajar con archivos; leer solo el payload del
registro principal pierde los datos que estan en continuaciones.
