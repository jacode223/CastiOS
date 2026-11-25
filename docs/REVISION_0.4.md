# Revisión de drivers y mejoras — CastiOS 0.4

Auditoría del código 0.3 recuperado, contraste con documentación primaria y
pruebas de regresión en QEMU/SeaBIOS. No equivale a validación de hardware físico.

## Bugs encontrados y corregidos

| Hallazgo del código 0.3 | Efecto | Corrección y verificación |
| --- | --- | --- |
| `driver_invoke` aceptaba cualquier EDX devuelto | Un consumidor podía interpretar más bytes de los solicitados | Comparar con la capacidad original en read/write; EIO y cero bytes si se excede. Fixture `overflow_test` |
| Callback podía dejar IF desactivado | El reloj dejaba de avanzar y futuros drivers IRQ podían detenerse | Guardar/restaurar flags alrededor del callback; fixture retorna con CLI y comprueba IF |
| Probe que reclamaba una IRQ y devolvía ENODEV no la liberaba | Dispositivo absent con IRQ aún habilitada | Liberar IRQ también en la ruta absent; fixture de IRQ10 |
| Última IRQ secundaria liberada dejaba IRQ2 desenmascarada | Cascada PIC habilitada sin propietario secundario | Reenmascarar cuando no queda ningún callback en IRQ8–15; prueba del registro PIC |
| `driver_register` desreferenciaba EBX=0 | Excepción en un registro inválido | Rechazo de descriptor nulo y nombres vacíos o de más de 15 caracteres |
| ABI no se comprobaba después del registro | Descriptor modificado podía seguir recibiendo llamadas | Comprobar ABI en cada operación |
| Detector ATA miraba estado/firma sin IDENTIFY | No conocía la capacidad ni verificaba soporte LBA | IDENTIFY DEVICE, bit LBA y capacidad en sectores; validar límites antes de transferir |
| Generador contaba cadenas `dd `, incluso en comentarios | El límite podía calcularse mal | Parsear declaraciones sin comentarios y exigir terminador |
| Arranque antiguo asumía geometría de disquete | Copiarlo a un disco duro no ofrecía un instalador válido | Cargador de disco EDD independiente, probado sin CD |

La comprobación de EDX detecta un retorno inválido; no evita que un callback
defectuoso haya escrito previamente fuera de su buffer. Los drivers siguen
ejecutando en ring 0. Los punteros son de confianza, no hay aislamiento de memoria.

## Drivers nuevos

| Driver | Implementación | Prueba |
| --- | --- | --- |
| serial | UART COM1 compatible 16550, prueba loopback, 115200 8N1, FIFO, polling TX con límite y RX no bloqueante | Escritura observada en chardev de QEMU; ausencia sin COM1 y lectura vacía sin bloquear |
| pci | Lectura de configuración CF8/CFC, buses/dispositivos/funciones, buffer de 128 entradas de 12 bytes | Identificación del host bridge de QEMU y presencia en registro de drivers |

PCI devuelve registros binarios `(BDF, vendor/device, class/revision)` little
endian. BDF codifica `(bus << 8) | (device << 3) | function`. El comando `pci`
los muestra en hexadecimal. `pci_truncated` indica que hubo más de 128 funciones;
la API actual no exporta ese indicador mediante ioctl.

## Instalación comprobada

`install CONFIRM` comprueba el destino primario, su capacidad y que sus primeros
193 sectores estén vacíos. Copia una imagen del kernel conservada antes de la
inicialización, ASFS con checksum y finalmente el sector de arranque. Rechaza
el disco de datos anterior o un destino ya instalado. No es un instalador de
particiones. No presupone que los sectores posteriores estén vacíos.

El instalador host crea un archivo exclusivo, nunca sobreescribe. Ambos caminos
se prueban arrancando una VM nueva **sin unidad de CD**. Se verifican lectura,
escritura y persistencia tras cerrar la VM. ASFS mantiene compatibilidad con
imágenes de datos antiguas. El paquete incluye un disco de ejemplo instalado.

## Pendientes priorizados

1. Alta: journal o doble copia de ASFS. Un corte durante el guardado puede
   invalidar el checksum; actualmente se cae a RAM sin sobrescribir el disco.
2. Alta: aislamiento de drivers y validación de punteros; requiere paging y
   política de memoria. Una ABI por sí sola no da seguridad.
3. Media: recursos de puertos y IRQ por driver, arbitraje y exclusión para PCI
   CF8/CFC y ATA si se añade concurrencia. Hoy el modelo es monoprocesador.
4. Media: hacer pasar toda la consola/teclado/RTC por la misma API; actualmente
   hay adaptadores, pero algunas rutas internas usan bajo nivel directamente.
5. Media: IRQ y buffers de recepción para UART/teclado, contador de pérdidas y
   códigos de error más completos; las operaciones actuales usan polling.
6. Media: drivers PCI concretos como RTL8139/E1000; enumerar PCI no implementa red.
7. Media: detectar tamaños de sector distintos de 512, LBA48, AHCI/NVMe y varios
   discos. Solo se admite el primary master con sectores de 512 bytes.
8. Baja: módulos dinámicos y descarga segura. Los drivers siguen integrados al
   compilar; el límite del kernel es 32 KiB y el registro admite 16 drivers.

## Fuentes primarias consultadas

- TI: implementación y estado de transmisor en UART 16550:
  https://www.ti.com/lit/pdf/spra882
- EDK II / Intel: biblioteca de configuración PCI mediante CF8/CFC:
  https://github.com/tianocore/edk2/blob/master/MdePkg/Library/BasePciCf8Lib/PciCf8Lib.c
- T13: Enhanced Disk Drive Specifications, documentos EDD:
  https://www.t13.org/docsearch?title=Enhanced%20Disk%20Drive
- Intel ICH7: controladores 8259 y registros de plataforma:
  https://www.intel.com/content/dam/doc/datasheet/i-o-controller-hub-7-datasheet.pdf
- QEMU: discos RAW/IDE y redirección serie para pruebas:
  https://qemu-project.gitlab.io/qemu/system/invocation.html

Las decisiones particulares de formato ASFS, ABI e instalación son de este
proyecto; no se presentan como parte de esos estándares.
