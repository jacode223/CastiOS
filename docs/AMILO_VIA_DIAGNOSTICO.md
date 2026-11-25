# VIA VT6421: soporte experimental de solo lectura

Las fotos del Amilo M3438G mostraron PCI 1106:3249, BAR0=0x0000dc01 y BAR1=0x0000db81. El driver comprueba el ID PCI, que el firmware haya habilitado la decodificacion de E/S y que ambos BAR individuales sean de E/S validos y alineados. Para cada uno de los dos puertos SATA, sondea IDENTIFY con tiempos de espera y registra unidades ATA admitidas en huecos libres del inventario. Usa los BAR informados por el firmware, no las direcciones fijas de la foto.

La implementacion usa PIO y comandos ATA LBA28, solo sectores logicos de 512 bytes y acceso de lectura. No modifica configuracion PCI, no efectua COMRESET ni configura el enlace SATA. El firmware debe dejar la controladora y los puertos operativos. No se ha probado el controlador VIA en hardware real ni en una emulacion VT6421. La maquina podria no detectar la unidad o no arrancar correctamente. Si identifica un disco se muestra VIA VT6421 solo lectura en `disks`.

Las rutas de escritura ATA y flush rechazan expresamente los dispositivos VIA. El sistema no implementa RAID de VIA ni NTFS: detectar un disco Windows no implica poder leer sus archivos ni reconstruir RAID. No se garantiza compatibilidad con arreglos o metadatos de la controladora. No uses install ni intentes guardar datos en ese disco. Usa una copia de seguridad y, preferentemente, una unidad de pruebas sin datos.

Compilacion y comprobaciones de no regresion en QEMU no verifican la ruta VIA porque QEMU no reproduce aqui esta controladora. En el Amilo, arranca desde USB y ejecuta `disks`; envia una foto completa, indicando si el equipo arranco y si aparece modelo/capacidad. Si se bloquea, apagar, retirar el USB y comunicar en que pantalla se detuvo.
