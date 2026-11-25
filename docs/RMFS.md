# RMFS en CastiOS

`/ram` es un sistema de archivos temporal independiente de HSFS. Reserva paginas fisicas de 4 KiB a demanda, usa hasta 64 nodos para archivos y carpetas y hasta 16 paginas (64 KiB) por archivo, con maximo teorico 4 MiB de datos si hay RAM disponible. Se pierden al apagar o reiniciar. `raminfo` informa uso. Los archivos se leen con `cat`, `stat`, `ls`, `cd`, `pwd` y Speed; se escriben con `write`, `append`, `touch`, `mkdir`, `rm` y `cp /mnt/... /ram/...`. El editor `nano` aun opera solo en HSFS.

HSFS sigue en disco en la raiz `/` cuando existe volumen persistente. El viejo codigo de compatibilidad conserva una raiz temporal si no hay disco, pero la shell empieza en `/ram` y su uso normal va a RMFS. Los archivos normales HSFS usan hasta 3,84 MB en extents; `cp` importa archivos de hasta 100 MiB a una region contigua del disco, con las limitaciones explicadas en HSFS_GRANDES.md.
