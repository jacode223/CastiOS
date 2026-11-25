# CastiPS 0.1 - base de procesos para CastiOS x86-64

Primera integración funcional con el scheduler x64 existente. **No es un proceso POSIX**, ni un gestor capaz de cargar aplicaciones externas todavía.

## Funciones incorporadas

- Tabla fija de **32 PCB** de 64 bytes cada una. Se reservan dos ranuras CPL3 reales, más dos descriptores del kernel: PID 0 `idle` (informativo, BLOCKED porque no es una tarea planificable) y PID 1 `shell64` (shell en CPL0, no tarea de usuario planificable).
- PID de 32 bits monotónico; el PID se renueva cada vez que se reutiliza una de las dos ranuras de usuario, incluido `reap` y lanzamientos posteriores.
- Datos por proceso: PID, PPID, UID, GID, estado, código de salida (32 bits), ticks de CPU aprox. y nombre (máximo 23 caracteres).
- Estados: FREE, READY, RUNNING, BLOCKED, ZOMBIE. `ps` permite verlos una vez regresamos a la shell. `reap` retira entradas ZOMBIE sin interrumpir procesos vivos.
- Conserva la multitarea preemptiva de dos procesos aislados, con `CR3`, pilas de kernel y espacios CPL3 distintos, desde `multi64` y `multifault64`.
- Syscall `int 0x80` número **8: getpid()** (devuelve PID positivo); número **9: yield()** (devuelve cero, y si otro proceso está READY lo ejecuta inmediatamente).
- Prueba `pidtest64` valida `getpid`, `yield` y `getpid` estable dentro de una tarea; salida 0 si pasa, 77 si falla.
- Las tareas de prueba anteriores (`run64`, `fault64`, `multi64` ...) quedan registradas y muestran su salida como ZOMBIE hasta el próximo uso de ranura o `reap`.

## Shell

```
ps              # lista PCBs activos y zombies
pidtest64       # prueba de getpid/yield
multi64         # 2 tareas CPL3 con Round Robin PIT 100 Hz
multifault64    # una de las 2 tareas provoca una excepcion
reap            # recoge zombies (sin bloquear)
```

## Limitaciones honestas

- Solo **2 tareas CPL3 simultáneas**. Los otros PCB son reserva estructural; no son 30 espacios listos para ejecutar.
- Las tareas vienen **compiladas en el kernel**; `spawn/exec` desde archivos HSFS6.1 no está disponible.
- Shell de CPL0 síncrona: no se mantiene interactiva mientras las tareas se ejecutan. `ps` se ve después de sus salidas.
- Sin `kill`, `waitpid` bloqueante, señales, `fork`, FPU/SSE, liberación de marcos por tarea, multihilo, SMP ni cambio voluntario de prioridad.
- `yield()` funciona directamente entre dos tareas del `multi64`; para una sola tarea retorna 0 sin forzar una salida al shell.
- Los ticks no son medición precisa de CPU usada; cuentan interrupciones PIT observadas en CPL3.
- La entrada ZOMBIE se conserva únicamente en la tabla en RAM; se sustituye al volver a usar la ranura.

## Compilacion (Debian/Ubuntu)

```
sudo apt install make gcc gcc-multilib binutils nasm python3 grub-pc-bin grub-common xorriso qemu-system-x86
make             # rama i386 + preview x64
make x64         # solo ISO x64
make test-castips    # pruebas del codigo fuente y NASM si esta instalado
make run-x64-hsfs61 # QEMU con disco HSFS6.1
```

La ISO BIOS x64 se genera en `dist/CastiOS-x64-preview.iso`. La rama i386 y HSFS6.1 no se sustituyen. `make` requiere las dependencias de compilación; no instala paquetes del sistema.
