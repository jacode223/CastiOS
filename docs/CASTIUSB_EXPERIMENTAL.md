# CastiUSB i386 experimental (USB + FAT32 + RAM)

## Uso

```sh
make i386               # solo ISO i386 (make tambien construye x64)
make test-fat32-large   # prueba FAT32 alojada, sin QEMU
make test-usb-hid       # prueba HID alojada
make test-usb-large-vm  # requiere ISO, QEMU, mkfs.fat, mtools
```

Con el pendrive conectado directamente (sin hub), en CastiOS:

```
usbscan
usbinfo
volumes
mount usb0p1 /mnt/usb
ls /mnt/usb
cat /mnt/usb/HELLO.TXT
```

Si FAT32 ocupa todo el dispositivo sin particion, usar `mount usb0 /mnt/usb`.
Los comandos se pueden ejecutar tambien mediante `castctl`.
`usbscan` invalida montajes USB existentes; montarlos nuevamente tras cada scan.
No hay deteccion automatica al enchufar. No formatear una unidad para probar.
El acceso USB/FAT32 se mantiene estrictamente de solo lectura.

## Cambios

- `usb_xhci.h`: nuevo controlador xHCI USB 3.x, PCI/MMIO, apropiacion BIOS,
  DMA, DCBAA, scratchpads (hasta 64), anillos de comandos/eventos/transferencias,
  contextos de 32/64 bytes, root ports, direccionamiento, EP0 y endpoints bulk.
  Admite velocidades USB 1/2/3 conocidas (IDs 1,3,4 para almacenamiento) y BOT.
- `usb_uhci.h`: controlador USB 1.1 full-speed para Intel/VIA compatibles UHCI,
  I/O PCI, frame list, QH y TD, reset de puerto, control y bulk con data toggles.
  Low-speed/teclado USB no soportados por este backend.
- `usb_storage_hosts.h`: deteccion PCI en una sola pasada; elige controlador
  por tipo y prueba otros si el primero no obtiene discos (EHCI conserva HID).
- `usb_ehci.h`: ruta MSC/SCSI compartida; EHCI conserva HID. Mejor gestion de
  cambios de puerto, cesion de puertos a controladoras companion, TUR antes
  de capacidad, reintentos, diagnostico de sectores no soportados y LBA32.
  Transferencias de hasta 6 sectores, cache secuencial bajo demanda de 4 KiB.
  UHCI prelectura hasta 2 sectores. No hay escritura SCSI.
- `fat32.h`: cache de un sector FAT, detector de ciclos Brent de memoria
  O(1) en vez del vector de hasta 4096 clusters y busqueda lineal O(n^2).
  GPT verifica la tabla completa una vez con CRC antes de listar los registros,
  en vez de verificarla una vez por particion. Geometria BPB con bounds seguros.
- `base.h`: espera breve activa y luego HLT con IF=1 hasta PIT (100 Hz), con
  timeout; operaciones C de copia/zero usan instrucciones de cadena x86.
- `rmfs.h`: tabla de nodos paginada (32 nodos por pagina), paginas de datos
  liberadas al borrar/truncar y pagina de metadatos liberada al quedar vacia.
  Copias por tramos de pagina en vez de dividir por pagina en cada byte.
- `bridge.asm`: adaptador CDECL para free_page (recibe puntero por pila).
- `nasm_runtime.ld`: alineacion de datos a 32 bytes para aprovechar espacio;
  el kernel i386 ya usa paginacion de identidad RW para esta region.
- Se mantiene el swap cooperativo de 100 KiB, HSFS, Castic y rama x64.

## Limitaciones / seguridad del experimento

No se ha arrancado en QEMU ni probado hardware real. Los nuevos drivers
son implementaciones originales experimentales, no ports completos de Linux.
Sin OHCI, hubs, UAS, escritura USB, exFAT ni FAT32 con sectores logicos de 4096.
Un controlador activo por tipo (intenta otros hasta hallar uno utilizable),
cuatro discos USB totales, 4 montajes FAT32. xHCI no implementa HID ni recuperacion
completa de endpoints detenidos: ante fallo requiere usbscan. UHCI es full-speed
para almacenamiento. No soporta MMIO por encima de 4 GiB ni velocidades xHCI
con IDs personalizados. `READ CAPACITY(10)` y LBA de 32 bits limitan a menos de
2 TiB con sectores de 512 bytes. La capacidad FAT32 de un dispositivo de 64 GB
no es un problema si su formato/sector logico y controlador son compatibles.
Los limites superiores de importacion/edicion del sistema se conservan;
no se promete leer archivos FAT32 de 4 GB en memoria. Usar medios de prueba.

## Referencias tecnicas (sin copiar codigo GPL/LGPL)

- Intel xHCI rev. 1.2: https://cdrdv2-public.intel.com/625472/625472_xHCI_Rev1_2b.pdf
- OSDev xHCI: https://wiki.osdev.org/XHCI
- OSDev UHCI: https://wiki.osdev.org/UHCI
- OSDev EHCI: https://wiki.osdev.org/Enhanced_Host_Controller_Interface
- OSDev MSC: https://wiki.osdev.org/USB_Flash_Memory
- SeaBIOS UHCI (referencia de comportamiento): https://github.com/coreboot/seabios/blob/master/src/hw/usb-uhci.c
- Microsoft FAT specification: https://www.scs.stanford.edu/~zyedidia/docs/_other/fat.pdf
