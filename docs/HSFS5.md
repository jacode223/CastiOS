# HSFS5: alcance y límites

Formato con 480 registros de 8192 bytes y cabecera de 512 bytes. Cada registro usa 64 bytes de metadatos y hasta 8000 bytes de datos; los ficheros grandes encadenan extents. Dos copias completas con suma de comprobación, situadas a 4 MiB de distancia. El limite teorico de un fichero normal en extents es 480 × 8000 = 3 840 000 bytes. Para archivos importados con cp, la extension de tipo 5 usa sectores del disco separados, hasta 100 MiB. Consulta HSFS_GRANDES.md.

Al guardar, HSFS incrementa la generación, escribe primero los sectores de
datos del espejo y vacía la caché del dispositivo. Después escribe su
cabecera con suma de comprobación y vuelve a vaciar. Repite el protocolo
para la copia principal. Al montar, escoge la copia válida más reciente.
Una interrupción durante cualquiera de los pasos deja recuperable una de
las dos copias de metadatos. La garantía supone que el dispositivo respeta
el comando de vaciado; no cubre corrupción simultánea de las dos copias,
sectores dañados ni los datos externos de archivos grandes: aún no hay
journal, comprobación por bloque ni transacciones de datos de usuario.

Migración sin sobrescritura mediante `tools/install_disk.py` y `tools/fs_format.py`: ASF4 anterior (256 bloques) se valida y amplía a HSFS5; la herramienta conserva índices, carpetas y extents y recalcula suma. Si ambas copias antiguas son inválidas, se rechaza la imagen.

Rutas: `/` desde raíz, relativas desde `cwd`, componentes `.` y `..`; `ls /docs` y `ls /docs/nota.txt` funcionan. No admite enlaces simbólicos, permisos POSIX, UTF-8 en nombres ni superar el tamaño fijo del volumen. NASM requiere 200 MiB en la configuración completa; el driver de disco tiene ventana LBA28. La actualización del formato no convierte un disco de 80 GiB en un volumen HSFS de 80 GiB.
