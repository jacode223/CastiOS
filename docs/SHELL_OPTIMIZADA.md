# Shell bitmap ligera e historial de pantalla

La interfaz es una shell de comandos con prompt CastiOS>, fondo oscuro
sin cabecera decorativa y fuente bitmap monoespaciada. No es DOS ni ejecuta
programas .COM/.EXE de DOS. Conserva los comandos, rutas y aplicaciones
AX05 de CastiOS.

## Teclas

- PgUp: retroceder 12 líneas en el historial de pantalla.
- PgDn: avanzar 12 líneas.
- Escribir, Enter, borrar o usar el historial de comandos devuelve la vista
  al final antes de realizar la acción. La línea de entrada sigue intacta.
- Arriba/abajo conserva el historial de comandos anterior.
- Tab conserva el autocompletado.

Se conservan las últimas 256 líneas que abandonaron la pantalla. Al llenarse,
las más antiguas se sustituyen: no crece el uso de memoria.
El historial es de la sesión, no se escribe al disco.
La pantalla actual de 25 líneas se mantiene aparte; ver el pasado no modifica
el buffer de salida ni la entrada. PgUp/PgDn se habilitan en readline de la
shell; no cambian las teclas del editor nano. `clear` limpia la pantalla actual,
sin borrar el historial ya guardado.

## Comandos familiares

Los nombres actuales siguen la shell Unix: `ls`, `cat`, `clear`, `cp`
y `uname`. Las funciones propias están bajo `castctl`.

Las importaciones ASCII de hasta 8000 bytes se guardan como texto nativo,
para poder leerlas con `cat`; otros contenidos conservan su tipo binario.

Los nombres de comando no distinguen mayúsculas/minúsculas. Las rutas siguen
usando / y los montajes /mnt; no se introducen letras de unidad ni rutas DOS.
`ls` y `cat` funcionan también en los montajes externos.

## Coste de memoria y dibujo

La fuente por defecto tiene 4096 bytes, se incluye en el kernel y no necesita
cargar una TTF ni rasterizar contornos. Las TTF siguen siendo opcionales.
En framebuffer se conserva la cuadrícula 80x25 y las celdas de 12x24 píxeles.
El perfil VGA de texto sigue disponible con CASTIOS_VIDEO=text bash build.sh.

El historial puede crecer hasta 16 páginas de 4096 bytes, con 16 líneas de
160 bytes por página; empieza sin reservarlas y añade una al llenar las
anteriores. La vista de scroll se reserva al usar PgUp y la caché de celdas
solo si el framebuffer está activo: máximo 72 KiB. Si falla una asignación,
el historial conserva la capacidad alcanzada. No guarda píxeles.

La caché evita pintar celdas cuyo carácter y atributo no han cambiado.
El cursor fuerza solo el repintado de sus celdas. Al cambiar la fuente o
limpiar el framebuffer se invalida la caché completa.
nano compone la pantalla en RAM y aplica las diferencias al terminar,
evitando limpiar y repintar el framebuffer con cada tecla.
El scroll normal guarda una línea y mueve celdas; una vista diferente puede
requerir repintar muchas celdas. No hay aceleración GPU ni afirmación de una
velocidad concreta sin mediciones en ese equipo.

## Memoria mínima comprobada

QEMU con 32 MiB: arranque, shell, framebuffer, ayuda, scroll, retorno al
escribir y memtest comprobados. Es una validación del funcionamiento básico,
no de todas las funciones a la vez ni de hardware físico.
NASM/TTF/importaciones grandes conservan sus condiciones anteriores
(200 MiB para el perfil completo desde 0.22). No se anuncia todo el SO como compatible
con 32 MiB por haber probado la consola.

## Pruebas

    QEMU_EXTRA_ARGS="-m 256" python3 tools/test_shell_scroll.py
    QEMU_EXTRA_ARGS="-m 256" python3 tools/test_fb_nano.py
    QEMU_EXTRA_ARGS="-m 256" python3 tools/test_08.py

Se comprobó el llenado y vuelta del anillo de 256 líneas, límites de
desplazamiento, conservación del buffer actual, retorno al escribir,
alias, editor, persistencia y NASM. Véase SHELL_VALIDACION.txt.
Las capturas son del sistema real emulado en QEMU. VirtualBox/hardware físico
siguen pendientes de validación directa.
