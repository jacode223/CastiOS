# ABI de syscalls AX05 y Speed — CastiOS 0.26

Las aplicaciones AX05 validadas con `exec`, `execall` o `bg` se ejecutan en
CPL3 y entran al kernel con `int 0x80`. Se usan registros de 32 bits. EAX
contiene el numero de syscall; EBX y ECX llevan los argumentos; el resultado
queda en EAX. Los demas registros se conservan. Los errores son negativos
en EAX, representados como enteros de 32 bits. No es la ABI de Linux.

| EAX | Nombre | Entrada | Resultado |
| --- | --- | --- | --- |
| 1 | exit | EBX=codigo | Termina el proceso; `exec` muestra el codigo |
| 2 | yield | ninguna | Cede CPU si hay varios procesos; EAX=0 al volver |
| 3 | getpid | ninguna | 1 para `exec`; 1..4 para ranuras de `execall`/`bg` |
| 4 | ticks | ninguna | Ticks PIT desde el arranque, aproximadamente 100 por segundo |
| 5 | write | EBX=puntero, ECX=longitud | Numero de bytes escritos |
| 6 | open | EBX=nombre, ECX=longitud | FD 3 o error |
| 7 | read | EBX=3, ECX=buffer, EDX=longitud | Bytes leídos, 0 al final o error |
| 8 | close | EBX=3 | 0 o error |
| 9 | stat | EBX=nombre, ECX=longitud, EDX=buffer | 0 o error; escribe dos `uint32`: tipo y tamaño |
| 10 | file_write | EBX=3, ECX=buffer, EDX=longitud | Bytes guardados o error |
| 11 | speed_key | ninguna | Código ASCII de una tecla, bloqueo hasta pulsación |
| 12 | speed_rect | EBX=x, ECX=y, EDX=ancho, ESI=alto, EDI=RGB | 0 si se dibujó, error si no |
| 13 | speed_text | EBX=x, ECX=y, EDX=RGB, ESI=puntero, EDI=longitud | 0 si se dibujó, error si no |
| 14 | speed_clear | ninguna | Limpia la consola; 0 |
| 15 | swap_alloc | ninguna | Dirección `0x20004000` de una página privada, o error |
| 16 | swap_out | ninguna | Guarda la página en disco y libera RAM; 0 o error |
| 17 | swap_in | ninguna | Restaura la página desde disco; dirección o error |
| 18 | sleep | EBX=ticks (1..10000) | Bloquea una tarea `bg`; 0 al despertar |

Las llamadas 15..18 se explican en [SWAP.md](SWAP.md). `swap_alloc`,
`swap_out` y `swap_in` son para AX05 y no admiten Speed; `sleep` solo
funciona en tareas AX05 de segundo plano. La página nueva es válida para
los buffers `read`, `write` y `file_write` mientras está en RAM.

La syscall 5 (`write`) acepta 0..256 bytes por llamada. Si la longitud no es cero, todo
el rango debe estar dentro de una sola pagina del propio proceso: codigo
`0x20000000..0x20000fff`, pila `0x20002000..0x20002fff`, la página
opcional de swap `0x20004000..0x20004fff` si está en RAM, o una página
bajo demanda presente en `0x20008000..0x2000bfff`. Admite texto
ASCII imprimible y salto de linea (LF=10). Valida el rango y todos los bytes
antes de producir salida. Para EAX desconocido devuelve `-38` (ENOSYS),
para puntero no valido `-14` (EFAULT), y para longitud o bytes no validos
`-22` (EINVAL). Longitud cero devuelve cero sin acceder a EBX.

Las llamadas 11..14 están reservadas al intérprete Speed lanzado por
`castctl speed` y devuelven `-38` en otras apps AX05. Speed tiene cuatro
páginas adicionales para el script en `0x20001000..0x20004fff` y pila en
`0x20006000..0x20006fff`, separada por una página de guardia. La syscall
13 acepta 1..128 bytes ASCII imprimibles dentro de una sola página; copia
el texto al kernel antes de dibujar. La 12 valida tamaño y coordenadas.

`open` y `stat` aceptan nombres de 1..31 caracteres ASCII de la raíz,
sin barras (`.` y `..` como nombre completo se rechazan). `open` admite
archivos normales HSFS y apps AX05, con un único descriptor 3 por proceso.
`read` avanza su posición y admite 0..256 bytes por llamada. `stat` escribe
tipo y longitud en 8 bytes de una sola página del proceso. Los buffers
de `read` y `file_write` siguen la misma regla de página indicada arriba.
`file_write` requiere además capacidad concedida al binario AX05 mediante
`chmod APP.app +w`; sin ella devuelve `-13` (EACCES). `-w` la revoca para
los próximos lanzamientos. `file_write` modifica un archivo de texto normal existente, contenido en
un registro (máximo 8000 bytes), desde la posición del descriptor, con
0..256 bytes ASCII imprimibles o LF. Sin `seek`, hay que leer hasta la
posición deseada antes de escribir; la longitud cero no cambia el disco.
No crea, borra, trunca ni amplía extents. Devuelve `-2` si falta el nombre,
`-9` si FD 3 no está abierto, `-21` para tipo no admitido, `-30` si el
volumen es de solo lectura o el archivo no es texto simple, `-5` ante
fallo de escritura, además de `-14` y `-22` para punteros y datos inválidos.
No hay permisos por usuario; la capacidad de escritura se guarda en el
registro HSFS de la app. Se recomienda usar solo apps de confianza
en discos con datos importantes.

Ejemplo desde la shell:

```text
castctl write pid.asm bits 32
castctl append pid.asm mov eax, 3
castctl append pid.asm int 0x80
castctl append pid.asm ret
castctl asm pid.asm pid.app
exec pid.app
```

El ensamblador reducido `castctl asm` acepta `mov eax,NUM`, `mov ebx,NUM`,
`mov ecx,NUM`, `mov edx,NUM` e `int 0x80`; no ensambla etiquetas ni
datos arbitrarios. `getpid` devuelve el numero de ranura, que puede
reutilizarse despues. `write` comparte la consola con la shell; la
intercalacion visual de varios procesos no esta garantizada. No hay todavia
syscalls de rutas completas, asignación dinámica general, teclado general, procesos
hijo ni permisos por usuario. NASM y drivers siguen en CPL0; el intérprete
Speed corre en CPL3, aunque su cargador y primitivas de dibujo son servicios
privilegiados.
