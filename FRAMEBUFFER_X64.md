# Consola framebuffer x86-64

GRUB solicita un framebuffer lineal RGB de 1024×768 y 32 bits. La consola x64 usa una fuente de 8×16 píxeles incluida en el kernel y una zona de 80×25 caracteres. El texto se desplaza automáticamente al alcanzar la última línea. La salida de depuración por el puerto 0xE9 sigue disponible.

Se comprueban dimensiones, formato y dirección del framebuffer antes de usarlo. Esta versión admite direcciones físicas por debajo de 1 GiB o entre 3 y 4 GiB; el área de 3–4 GiB se mapea sin permisos de usuario, compartida con el mapeo MMIO de AHCI. No se reserva una copia de toda la pantalla en RAM. Si el formato o la dirección no son compatibles, el kernel utiliza su ruta VGA de texto anterior. Esa ruta solo será visible si el firmware mantiene un modo de texto VGA; no se cambia automáticamente de modo desde el kernel.

El área dibujada ocupa la esquina superior izquierda (640×400), con caracteres blancos sobre negro. La gestión de ventanas, colores y resoluciones arbitrarias no forma parte de esta versión. Es una implementación experimental para BIOS/GRUB Multiboot de 64 bits, no un controlador específico de GPU ni soporte UEFI nativo. La conexión física del monitor depende del firmware y la tarjeta gráfica.

Compilar con `make x64` o `make`. La imagen se genera en `dist/CastiOS-x64-preview.iso`.
