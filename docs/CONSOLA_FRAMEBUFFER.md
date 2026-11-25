# Terminal framebuffer — CastiOS 0.8

Esta revisión usa el framebuffer lineal entregado por GRUB para dibujar la
terminal. No añade un escritorio ni ventanas. AHCI/IDE y ASFS siguen integrados.

## Cambios visibles

- Modo solicitado 1024x768, RGB de 32 bits.
- Terminal de 80x25 celdas centrada, glifos de 12x24 píxeles.
- Fondo oscuro, paleta de 16 colores, cabecera y línea de acento.
- Cursor de subrayado dibujado por software.
- Scroll vertical, borrado, clear, historial y autocompletado existentes.
- nano dibuja ahora sus celdas a través del mismo renderizador.
- console informa del modo y resolución activos.

## Arquitectura

src/console/framebuffer.asm implementa el renderizador NASM.
Hay un buffer de celdas en RAM (term_cells): no se lee la memoria VGA para
reconstruir texto en un modo gráfico. Cada celda conserva carácter y atributo.
putc y nano usan ese buffer y actualizan el framebuffer.
El scroll mueve las celdas y repinta la terminal; no lee píxeles de VRAM.
No se repinta desde IRQ. No hay aceleración GPU ni doble buffer.

Se valida Multiboot1 flags[12], dirección bajo 4 GiB, tipo RGB, bpp, canales,
dimensiones y pitch. Los campos RGB tienen el padding de la estructura GRUB.
Se mapea todo pitch*height sin caché mediante el helper de mapeo MMIO existente.
No se presupone que pitch sea width*4. La memoria del framebuffer no es heap.

El perfil actual acepta RGB32 con canales R16/G8/B0 de 8 bits, anchos
1024..4096, altos 768..2160 y pitch limitado. GRUB solicita 1024x768.
No hay soporte de otros formatos de píxel, HiDPI, Unicode, ratón o modos
seleccionables desde la shell. La fuente es bitmap CP437; la entrada sigue
usando el teclado del sistema.

La interfaz conserva 80x25 para mantener las posiciones y contratos de nano.
El driver lógico llamado vga conserva ese nombre por compatibilidad con
comandos anteriores; su escritura pasa ahora por putc.

## Construcción y fallback

    bash build.sh

El modo VGA de texto sigue disponible como perfil de compilación:

    CASTIOS_VIDEO=text bash build.sh

Este perfil cambia tanto la petición Multiboot como gfxpayload.
Solo cambiar gfxpayload no basta para anular la petición gráfica del kernel.
Para volver a la entrega gráfica, ejecuta bash build.sh sin esa variable.

La detección usa la información de GRUB, no un driver específico de la GPU.
Se necesita un framebuffer compatible con el perfil anterior. El fallback
VGA es útil al arrancar en modo de texto; no convierte automáticamente un
modo gráfico desconocido a texto.

## Fuente

font8x16.bin está rasterizada desde DejaVu Sans Mono (13 px) y escalada
a 12x24 por tablas de muestreo. La licencia se incluye en
src/console/FONT-LICENSE.txt. No se necesita Pillow para compilar el SO.

## Validación

    QEMU_EXTRA_ARGS="-m 256" python3 tools/test_framebuffer.py
    QEMU_EXTRA_ARGS="-m 256" python3 tools/test_fb_nano.py
    QEMU_EXTRA_ARGS="-m 256" python3 tools/test_08_regression.py
    QEMU_EXTRA_ARGS="-m 256" python3 tools/test_ahci.py
    QEMU_EXTRA_ARGS="-m 256" python3 tools/test_08.py

Las capturas provienen del framebuffer real de QEMU, no de un mockup.
Véase CONSOLA_VALIDACION.txt. VirtualBox y hardware físico no validados.
