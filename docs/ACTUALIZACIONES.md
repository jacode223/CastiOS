# Actualizaciones internas A/B — CastiOS 0.25

Arranca `CastiOS-hdd.img` desde disco con BIOS/GRUB, al menos 200 MiB de
RAM, y HSFS persistente en el mismo disco. Hay dos entradas de GRUB:
**Estable**, que el actualizador nunca sobrescribe, y **Nuevo**, una
reserva de 128 KiB. GRUB deja cinco segundos para escoger.

```text
nano /src/process.asm
castctl kbuild
castctl kapply kernel.img
castctl kstatus
reboot
castctl kaccept
```

`kbuild` ensambla `/kernel.img` dentro de CastiOS con NASM; un fallo de
ensamblado no publica la imagen candidata. También puedes importar un
kernel Multiboot compatible desde FAT32 con `cp /mnt/kernel.img /kernel.img`.
`kapply` admite el archivo normal HSFS o el archivo grande de HSFS. Rechaza
longitudes fuera de 64..131072 bytes, tipos distintos y cabeceras Multiboot
incompatibles. Comprueba el disco de arranque, selecciona Estable, escribe
Nuevo, fuerza el vaciado de caché, relee y compara todos los sectores,
y por último selecciona Nuevo. Un error antes del último paso deja elegida
la copia Estable. La entrada Estable no se sobrescribe.

La candidata tiene un intento: después de detectar el disco y antes de
montar HSFS, prepara Estable para el siguiente arranque. Si la prueba funciona, ejecuta
`castctl kaccept` en la sesión candidata y confirma la selección permanente.
Si no la confirmas, el siguiente reinicio arranca Estable. `kaccept` desde
Estable se rechaza. Si Nuevo se bloquea antes de detectar el disco,
**elige CastiOS estable en GRUB con las flechas**; no hay temporizador capaz de detectar ese
bloqueo. `castctl krollback` seguido de `reboot` fuerza Estable desde una
shell funcional. `kstatus` muestra la selección persistida.
La selección queda en el disco, no en HSFS. `kapply` solo opera sobre una
imagen HDD preparada por CastiOS 0.21 o posterior con el diseño de sectores previsto;
no modifica discos ajenos ni arranques desde la ISO Live.

La comprobación de cabecera y la lectura posterior detectan imágenes
claramente inválidas y errores de escritura; no garantizan que código
arbitrario funcione. No hay watchdog si Nuevo falla antes de llegar al
controlador de disco. Cambios en Speed C, los servicios C y GRUB siguen
requiriendo GCC/ld y herramientas del anfitrión.
