# USB HID en CastiOS i386

`castctl usbscan` busca dispositivos conectados a los puertos raiz de un controlador USB 2.0 EHCI. Detecta interfaces HID boot de teclado y raton, selecciona protocolo boot y sondea los informes por endpoints interrupt IN. Hay una cola periodica por dispositivo, con un teclado y un raton activos a la vez. `castctl usbkbd` muestra detalles del teclado. El raton actualiza las coordenadas y botones compartidos con el escritorio.

El teclado acepta informes de ocho bytes y filtra rollover y duplicados. El raton acepta el informe boot de tres bytes (movimiento relativo y tres botones). Una desconexion se detecta al sondear; se liberan las teclas o botones y se mantiene el otro dispositivo. Tras conectar uno nuevo hay que ejecutar `castctl usbscan` de nuevo. El indicador `mousestat` conserva una etiqueta PS/2 historica incluso al compartir las coordenadas con un raton USB.

Limites: solo puertos raiz EHCI de alta velocidad admitidos por el controlador, un teclado activo y un raton activo; no se admiten hubs, controladoras xHCI/OHCI/UHCI, el parser general HID, rueda ni funciones especiales. Muchos perifericos USB de velocidad baja o completa y equipos antiguos requieren un companion controller; no se garantiza que funcionen. Esta es una implementacion propia, no incluye codigo fuente de los drivers Linux. No se ha probado en hardware fisico.

Prueba `python3 tools/test_usb_mouse_i386.py` y `python3 tools/test_usb_keyboard.py` con QEMU tras compilar. La prueba conjunta con disco USB requiere `mkfs.fat` y mtools.
