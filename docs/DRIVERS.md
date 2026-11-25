# Crear drivers para CastiOS 0.5

Cambios actuales: PS/2 usa IRQ1 y cola; ATA detecta hda/hdb mediante IDENTIFY.
La API de bloques acepta LBA relativo 0..512 y suma fs_base (0 o 128) en el
disco seleccionado. El driver rechaza accesos por encima de su capacidad.
Los descriptores anteriores conservan la ABI v1. El formato de disco ahora
es ASFS2, documentado en README.md. Las secciones historicas siguientes que
describen 64 sectores corresponden a la version 0.4.

Consulta `REVISION_0.4.md` para los bugs corregidos, drivers serial/PCI y pendientes.
El gestor conserva las flags alrededor del callback, valida la ABI y rechaza
cuentas read/write superiores a la capacidad original con EIO. La prueba
`drvtest` requiere dos espacios libres y IRQ10 disponible para sus fixtures;
los registros temporales se retiran al finalizar.

La ABI v1 permite integrar drivers NASM en el kernel de 32 bits. Hay registro
de hasta 16 drivers, detección (`probe`), inicialización (`init`), lectura,
escritura y control (`ioctl`). El kernel inicializa el manifiesto en orden.
El PIT registra su callback IRQ0 mediante esta API. Los accesos a sectores de
ASFS pasan por el driver ATA registrado. VGA, PS/2 y RTC tienen adaptadores de
la API; sus rutinas internas de consola, decodificación y reloj también siguen
usando sus funciones de bajo nivel directamente.

## Crear el primero

```sh
python3 tools/new_driver.py hello
bash build.sh
bash run.sh
```

El generador crea `src/drivers/hello.asm`, agrega su include al kernel y su
descriptor al manifiesto. No reemplaza drivers existentes. Dentro de CastiOS:

```text
drivers
drvinfo hello
drvread hello
drvwrite loopback Hola mundo
drvread loopback
drvtest
```

`hello` responde `Driver hello listo`. Edita su archivo para implementar el
hardware. La plantilla también está en `src/drivers/template.asm.txt`. Para
integrarlo manualmente, agrega un `%include` en `kernel.asm` y su descriptor
en `manifest.inc` antes de `dd 0`. Recompila y reinicia para aplicar cambios.

## Descriptor y estados

Usa `DRIVER descriptor, nombre, clase, probe, init, read, write, ioctl`.
Nombre y clase son punteros a cadenas ASCII terminadas en cero. Todos los
campos son dword de 32 bits; los offsets están en `abi.inc`.

| Offset | Campo |
| --- | --- |
| 0 | ABI = 1 |
| 4 | Puntero a nombre único |
| 8 | Puntero a clase (`text`, `block`, `input`, `timer`, `clock`) |
| 12 / 16 | Callback probe / init; cero equivale a éxito |
| 20 / 24 / 28 | Callback read / write / ioctl; cero = operación no soportada |
| 32 | Estado: 0 registered, 1 ready, 2 absent, 3 failed |
| 36 | Último error |

Los descriptores y buffers deben ser memoria válida del kernel. `probe` retorna
OK si detecta el dispositivo y ENODEV si no existe; otros errores significan
fallo. Solo los drivers ready reciben llamadas de E/S. Si init falla, el gestor
libera las IRQ que registró ese driver. No hay reintentos, descarga o reinicio
de drivers en caliente.

## Convenio de llamadas

Todos los callbacks retornan con `ret`, nunca con `iret`.

| Operación | Entradas | Salida |
| --- | --- | --- |
| probe / init | EBX = descriptor | EAX = estado |
| read / write | EBX = descriptor; EDI = buffer; ECX = capacidad o bytes | EAX = estado; EDX = bytes transferidos |
| ioctl | EBX = descriptor; EDX = opcode; EDI = buffer; ECX = capacidad | EAX = estado; EDX = bytes transferidos, cuando corresponda |

El gestor preserva EBX, ESI, EDI y EBP alrededor del callback. EAX, ECX, EDX
y las flags son volátiles. Mantén la pila equilibrada y no alteres segmentos,
la IDT o el estado de interrupciones. El gestor limpia DF al volver.
Las APIs se llaman `driver_read`, `driver_write`, `driver_ioctl` y validan que
el descriptor pertenece al registro. `driver_find` recibe ESI=nombre y retorna
EAX=estado, EDX=descriptor; EBX se conserva. `driver_register` recibe EBX=descriptor
estático y rechaza duplicados, ABI incompatible y registros por encima del límite.

Ejemplo de llamada desde código NASM integrado:

```nasm
mov esi, loopback_name
call driver_find
test eax, eax
jnz .error
mov ebx, edx
mov edi, mi_buffer
mov ecx, 100
call driver_read
; EAX=OK y EDX indica los bytes válidos; no se agrega terminador cero.
```

Errores: OK=0, ENODEV=1, ENOSYS=2, EINVAL=3, EBUSY=4, ENOSPC=5, EIO=6.
No des por hecho que el buffer recibido es una cadena: valida ECX antes de
escribir. No transfieras más bytes que la capacidad. Los comandos `drvread` y
`drvwrite` solo aceptan clase `text` y están limitados a 250 bytes.

## Interrupciones

`irq_register`: EAX=IRQ (0..15, excepto 2), ECX=callback, EBX=propietario
registrado. Retorna EAX=estado. El PIC se desenmascara automáticamente. Cada
IRQ admite un propietario; una IRQ ocupada retorna EBUSY. El callback recibe
EAX=IRQ y EBX=descriptor; el stub salva registros y realiza EOI e `iretd`.
Tu callback termina con `ret` y debe ser breve: no bloquear, no imprimir, no
esperar al disco. Usa buffers para procesar después. IRQ0 ya pertenece al PIT.
`irq_unregister`: EAX=IRQ, EBX=propietario; enmascara y libera solo si coincide.
Las modificaciones del registro IRQ preservan el estado previo de interrupciones.
No hay IRQ compartidas, APIC ni SMP.

## Drivers incluidos

| Nombre | Interfaz |
| --- | --- |
| vga | write: bytes a consola; sin read |
| pit | read: DWORD little endian de ticks, capacidad mínima 4; IRQ0 a 100 Hz |
| ps2 | read: un scancode crudo o cero bytes si no hay datos; no bloquea |
| ata | read/write: sector de 512 bytes, EDX=LBA relativo 0..64; write requiere ASFS validado; suma fs_base (0 o 128) |
| rtc | read: 8 bytes CMOS crudos: segundo, minuto, hora, día, mes, año, siglo, estado B |
| loopback | write: reemplaza buffer de hasta 250 bytes; read: copia hasta la capacidad |
| serial | COM1 115200 8N1, read no bloqueante y write con espera limitada |
| pci | read: registros binarios de 12 bytes, capacidad mínima count*12 |

ATA usa primary master y la transferencia PIO existente. La API de bloque es
síncrona; la política actual limita sus accesos al volumen ASFS. El vaciado de
caché al guardar el FS sigue en `sync`. PS/2 y la shell comparten la cola de
teclado: no añadas un segundo lector concurrente. RTC devuelve la codificación
del hardware, indicada por el estado B. Loopback ioctl 0 vacía el buffer;
ioctl 1 devuelve su longitud en un DWORD (capacidad mínima 4).

## Límites

Los drivers ejecutan en ring 0 y pueden acceder directamente a puertos y RAM.
La ABI no aísla código defectuoso ni valida todos los punteros: un driver
incorrecto puede bloquear el sistema. No es un formato de módulos dinámicos.
El binario completo del kernel mantiene el límite actual de 32 KiB.
`docs/VALIDACION.txt` recoge las pruebas de esta versión en QEMU.
