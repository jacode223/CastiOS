# Swap cooperativa en CastiOS 0.24

El kernel reserva los **últimos 100 KiB del disco HSFS** para swap. Por compatibilidad con kernels anteriores, el asignador de archivos grandes sigue excluyendo los últimos 4 MiB. Al usarla, el kernel comprueba que el volumen montado es persistente, que el controlador permite escribir y vaciar la caché, que caben los sectores y que ningún archivo grande existente ocupa la reserva. La ISO sin disco persistente no puede guardar páginas en swap.

Cada proceso AX05 tiene **una página de datos opcional de 4 KiB** en la dirección `0x20004000`. Hay una ranura por cada uno de los cuatro procesos concurrentes y otra para `exec`. Las syscalls permiten crear la página, guardarla en disco liberando el marco físico y recuperarla. El proceso debe llamar a `swap_in` antes de acceder a ella otra vez. Cuando termina, libera cualquier marco que haya recuperado.

La llamada `sleep` sirve para procesos AX05 en segundo plano (`bg`): bloquea de 1 a 10000 ticks, sin consumir turnos de CPU, y el planificador los vuelve a poner en ejecución al cumplirse el plazo. Una app que quiera ahorrar RAM guarda su página con `swap_out` antes de dormir y llama a `swap_in` al despertar. No se intercambian automáticamente el código ni la pila, que siguen ocupando RAM. Tampoco hay paginación por fallos de página ni ampliación automática de memoria.

| EAX | Llamada | Resultado |
| --- | --- | --- |
| 15 | `swap_alloc()` | `0x20004000`, o error; crea una página privada vacía |
| 16 | `swap_out()` | `0`, o error; guarda los 4096 bytes, fuerza flush y libera el marco |
| 17 | `swap_in()` | `0x20004000`, o error; restaura el contenido y remapea el marco |
| 18 | `sleep(EBX=ticks)` | `0` al despertar; solo para procesos `bg`, 1..10000 ticks |

Errores: `-38` no disponible (Speed o `sleep` fuera de `bg`), `-19` volumen no apto, `-12` sin marco libre, `-16` página todavía en disco, `-22` orden o duración incorrectos, `-5` E/S fallida. Las syscalls 15..17 usan el slot de la tarea actual: no aceptan un sector, una dirección física ni un PID arbitrario. La reserva no está cifrada y puede conservar datos tras finalizar el proceso: **no pongas secretos en esa página**.

La reserva de compatibilidad reduce en 4 MiB el espacio utilizable para archivos grandes HSFS en discos compatibles. Los datos en swap se descartan lógicamente al reiniciar; no hay persistencia de procesos.
