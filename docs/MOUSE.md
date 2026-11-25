# Ratón PS/2 en CastiOS 0.30

El driver integrado `ps2mouse` comparte el controlador i8042 con el teclado.
Durante el arranque habilita el puerto auxiliar, configura IRQ12 y comprueba
las respuestas del ratón antes de activar el registro de interrupciones.
Si falta o falla la inicialización, queda ausente sin impedir que funcione
el teclado. Los sondeos al controlador tienen límites de espera.

Procesa paquetes relativos de tres bytes, sincroniza la primera marca,
descarta desbordamientos y limita las coordenadas a la zona de 960 × 600.
`mousestat` imprime coordenadas y los bits de botones (1 izquierdo, 2 derecho,
4 central). `drivers` muestra el driver y `desktop` admite movimiento y clic
izquierdo sobre sus opciones. El cursor gráfico es un símbolo `+`.

No hay soporte para ratones USB, rueda, gestos ni aplicaciones con ventanas
propias. El escritorio sigue siendo un lanzador y su salida vuelve a la
terminal. La prueba `tools/test_mouse.py` usa el ratón emulado de QEMU.
