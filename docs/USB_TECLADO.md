# Teclado USB HID en CastiOS 0.32

`castctl usbscan` busca teclados USB HID **Boot Keyboard** en los puertos raíz del controlador EHCI y configura su interfaz en protocolo boot. `castctl usbkbd` muestra el puerto, VID/PID, endpoint interrupt IN e intervalo encontrados. La rutina `usb_hid.h` convierte informes boot de ocho bytes a códigos de teclado para letras, números y teclas básicas; una prueba en el anfitrión comprueba pulsación, liberación, repetición y error de rollover.

**Desde 0.32:** el primer teclado compatible ya tiene una planificación periódica interrupt IN, informes HID de ocho bytes y entrada por la misma cola que usa la shell PS/2. Los demás teclados detectados figuran en la lista, pero solo el primero recibe informes. La lectura periódica reserva dos páginas de DMA y las reutiliza entre escaneos.

La enumeración exige un dispositivo USB de alta velocidad conectado directamente a EHCI. Teclados de velocidad completa o baja, hubs, controladores UHCI, OHCI y xHCI no están cubiertos. En particular, la detección de un controlador EHCI por sí sola no prueba que un teclado típico de VirtualBox vaya a funcionar. Un dispositivo compuesto con almacenamiento se trata como disco para conservar la ruta anterior. Un ratón USB tampoco está cubierto.

Para probarla: ejecuta `castctl usbscan`, luego `castctl usbkbd`. Debe indicar `entrada activa` para el primer teclado compatible. La prueba `tools/test_usb_keyboard.py` conecta un teclado USB de alta velocidad emulado en QEMU, escribe un comando, lo desconecta y verifica que el teclado PS/2 sigue funcionando. `tools/test_usb_hid_storage.py` comprueba teclado y FAT32 simultáneos.

Desde 0.31, los discos USB EHCI tienen recuperación BOT ante fallos de
transporte, reintentos de lectura y REQUEST SENSE. `castctl usbinfo` muestra
conexión y contador de fallos por disco; `castctl usbscan` reenumera después
de conectar o retirar dispositivos e invalida montajes USB anteriores.
La lectura FAT32 sigue siendo de solo lectura.
