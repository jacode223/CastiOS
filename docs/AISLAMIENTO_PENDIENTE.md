# Protección de procesos y actualización del kernel: estado real

## Avance 0.22: intérprete Speed aislado

Speed se ejecuta como proceso CPL3 con CR3 propio, pila con guardia y
syscalls de texto, teclado y framebuffer. Las entradas desde usuario se
validan antes de llamar a las primitivas de dibujo privilegiadas. Un fallo
de página de Speed termina ese proceso y devuelve la shell. NASM, el
cargador de scripts, la shell y los drivers continúan en CPL0; los fallos
de kernel o de DMA no quedan aislados. Los apartados siguientes describen
las versiones anteriores y conservan su estado histórico.

## Avance 0.15: shell activa con tareas de fondo

`bg A.app` carga un proceso AX05 y vuelve inmediatamente al prompt.
Se pueden iniciar hasta cuatro tareas; el PIT alterna entre la shell CPL0
y cada proceso CPL3. `ps` muestra ejecutando o terminado, y `waitbg`
espera a todos, muestra sus EAX y libera páginas. Un proceso que termina
por error no detiene los demás. `run` y `run2` se rechazan mientras
queden tareas de fondo, hasta ejecutar `waitbg`.

No hay aún PIDs persistentes, señales, cancelación, IPC ni E/S de archivos
en apps de usuario. La shell sigue en CPL0, al igual que Speed, NASM y drivers.
Las llamadas síncronas de drivers de kernel pueden demorar los turnos del
planificador; los procesos CPL3 son interrumpidos por reloj.

## Avance 0.14: cuatro procesos y cesión voluntaria

`run2 A.app B.app [C.app D.app]` admite entre dos y cuatro procesos en
primer plano. El planificador recorre las tareas activas de forma circular.
Un proceso puede ceder el turno con `mov eax, 2` / `int 0x80`; la llamada
1 sigue siendo `exit`. Una llamada desconocida termina solo esa tarea
con código 4294967294. La prueba QEMU incluye cuatro bucles, una cesión
voluntaria, un fallo y el regreso a la shell.

Sigue sin existir multitarea de fondo ni API de ficheros de usuario;
Speed, NASM y controladores continúan en CPL0.

## Avance 0.13: dos procesos AX05 con planificación

`run2 A.app B.app` crea dos procesos CPL3 independientes. La IRQ0 del PIT
interrumpe al proceso activo y guarda sus registros y pila de interrupción;
un planificador round robin cambia CR3 y la pila de la TSS antes de reanudar
el otro proceso. Los procesos terminados liberan sus páginas al volver a la
shell. El comando informa de los cambios de contexto. Hay un máximo de dos
procesos, ambos en primer plano: la shell espera a los dos. La frecuencia
actual del reloj es 100 Hz. La prueba `tools/test_multitask.py` usa dos
bucles largos y exige cambios de contexto y resultados independientes.

Todavía no hay tareas en segundo plano, sincronización, prioridades, IPC,
espera de E/S ni cancelación. Speed, NASM, USB y los demás drivers siguen en
CPL0; los fallos de kernel y DMA no están aislados.

## Avance 0.12: ejecutor AX05 en CPL3

`run` ejecuta ahora el binario AX05 en CPL3 con un CR3 privado: la página de
código, la pila de usuario y una página de guardia tienen permisos de usuario;
el kernel, sus drivers y MMIO quedan en páginas supervisor. Una TSS proporciona
la pila de kernel para interrupciones y `int 0x80`; la llamada 1 termina el
programa y devuelve EAX a la shell. #PF, #GP y #UD del usuario devuelven el
control a la shell. El proceso termina y sus páginas se liberan al salir.
El comando `run` ejecuta un proceso AX05 cada vez. `run2` permite dos.
No existe aún una ABI general de ficheros.

Speed, NASM y drivers siguen en CPL0. Un fallo de kernel o DMA todavía puede
detener o corromper el sistema. El aislamiento de AX05 no constituye
aislamiento global de CastiOS.

CastiOS 0.10 ejecuta el intérprete Speed, el NASM incorporado, controladores y binarios AX05 en CPL0. La paginación actual usa un único CR3 y mapea memoria del kernel y MMIO para código privilegiado. Speed restringe sus instrucciones y valida coordenadas, longitud y saltos; esto reduce errores de scripts, pero **no aísla código nativo ni errores del propio intérprete**. Las rutas USB inválidas se desactivan en fallos y las lecturas posteriores se rechazan; un fallo de MMIO o un bug CPL0 aún podría detener el kernel.

Para implementar aislamiento real sin perder los drivers existentes:

1. GDT con segmentos de usuario CPL3, TSS y pila de kernel por proceso.
2. Espacio virtual por app con páginas U/S: código y datos de usuario, pila con página de guardia; kernel y MMIO sólo supervisor.
3. Entrada y salida a través de `int 0x80` validando rangos de punteros, longitudes y permisos; copiar buffers antes de llamar a drivers.
4. IDT con manejadores de #PF, #GP y #UD que terminan sólo la app cuando `CS.RPL=3`, conservando un diagnóstico para fallos del kernel.
5. Cargador AX05 en páginas privadas y contexto con EIP/ESP de usuario; ninguna app puede ejecutar `out`, `cli` ni tocar CR3.
6. Trasladar USB a un servicio controlado o limitarlo a supervisor con watchdog y recuperación por controlador; un simple manejador de excepciones no hace seguro el DMA de hardware.
7. Para reconstruir el kernel dentro de CastiOS: portar GCC/ld o reescribir las partes C en NASM, guardar fuentes en un volumen con espacio suficiente, compilar una imagen secundaria, verificar firma o checksum, arrancar desde ella y volver a la anterior si falla. Informar antes de activar el reinicio. La herramienta `tools/update_kernel.py` sólo reconstruye desde un anfitrión con la VM apagada y conserva los datos del disco.

No activar `CR0.WP` ni marcar páginas del kernel de solo lectura sin separar primero datos mutables de código: comparten páginas en la imagen actual. Tampoco intentar recuperar un fallo arbitrario de EHCI saltando una instrucción del kernel: podría dejar DMA activo y memoria corrompida.
