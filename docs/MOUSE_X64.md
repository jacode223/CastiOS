# Ratón PS/2 en CastiOS x86-64

`src/x64/mouse.asm` adapta el driver propio de CastiOS i386. Linux proporciona
el driver abierto `drivers/input/mouse/psmouse-base.c`, dependiente de sus
subsistemas serio/input: https://github.com/torvalds/linux/blob/master/drivers/input/mouse/psmouse-base.c.
Esta implementación no copia ni incluye código de Linux.

En el arranque se habilita el puerto auxiliar y se comprueban los ACK de
configuración mediante esperas acotadas. El bucle de la shell sondea i8042 y
separa los bytes de teclado y ratón con el bit de origen. El driver
sincroniza paquetes PS/2 de tres bytes, ignora los que indican desbordamiento,
actualiza coordenadas limitadas a 960 × 600 y mantiene los tres botones.
`mousestat` muestra `x`, `y`, máscara de botones y eventos. Botones: 1
izquierdo, 2 derecho y 4 central. La shell funciona si no hay ratón.

El sondeo sucede solo mientras la shell está activa; no es IRQ12 ni entrega
de eventos a aplicaciones. No dibuja cursor: el escritorio gráfico i386 aún
no se ha portado a x64. No hay soporte USB HID, rueda ni dispositivos PS/2
avanzados. La prueba QEMU mueve el ratón, pulsa un botón y comprueba que el
teclado y otras pruebas x64 siguen funcionando. No se probó hardware físico.
