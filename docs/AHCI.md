# CastiOS 0.8 — SATA/AHCI inicial

Se añade src/drivers/ahci.asm, integrado en el kernel completo.
No es un módulo externo para drvload.

## Implementación

- Detecta el primer controlador PCI clase 01/06/01 (AHCI), BAR5 de memoria
  bajo 4 GiB. Activa Memory Space y Bus Mastering.
- Mapea MMIO mediante tablas de páginas de identidad sin caché.
- Solicita BIOS/OS handoff cuando el controlador lo anuncia.
- Recorre los 32 bits PI, exige enlace activo y firma de disco SATA ATA.
- Detiene los motores antes de configurar CLB y FB. Reserva una página DMA
  por puerto: command list, received FIS, command table y bounce buffer.
- Envía IDENTIFY, READ DMA EXT, WRITE DMA EXT y FLUSH CACHE por slot 0.
- Polling síncrono, IRQ de HBA/puerto deshabilitadas. Sin NCQ.
- Valida capacidad y sectores lógicos de 512 bytes. Conserva la ventana
  de 128 GiB por disco de la ABI existente, aunque los comandos son EXT.
- Comprueba finalización, errores de transporte/ATA y los 512 bytes transferidos.
- Ante timeout/error desactiva ST y deja el puerto inutilizable hasta reiniciar.
  Retiene la página DMA: no libera ni reutiliza memoria potencialmente en vuelo.
  No intenta repetir escrituras, recuperar el enlace o resetear el HBA.
- El buffer del llamador nunca es destino DMA directo.
- Comparte las operaciones de ASFS4, montaje, espejo e instalación con IDE.
  Requiere FLUSH CACHE anunciado para permitir escrituras.

## VirtualBox

Apaga la máquina y conecta el disco a un controlador SATA de tipo AHCI.
Arranca esta ISO actualizada. Ejecuta disks: una unidad utilizable mostrará
SATA/AHCI en su línea. No basta con que aparezca en el inventario PCI.

Los nombres hda..hdd ahora son las cuatro entradas de almacenamiento del sistema:
primero IDE utilizable y después SATA en los huecos libres.
No equivalen al número de puerto SATA. Sin discos IDE, el primer disco SATA
utilizable será hda incluso si está en un puerto SATA alto.

Un disco nuevo sin ASFS hará que el sistema arranque en RAM aunque se detecte.
Para instalar, revisa disks y usa install hda (o la unidad que corresponda).
La confirmación FORMAT hda borra esa unidad. No es necesaria para diagnosticar.

## Alcance y pruebas

Se ha probado con AHCI ICH9 de QEMU, en máquinas PC y Q35, puertos 0 y 5,
lectura/escritura exacta, espejos ASFS, reinicio, instalación SATA sin ISO,
coexistencia con IDE y errores de lectura/escritura inyectados.
Consulta AHCI_VALIDACION.txt para resultados y hashes.

No se ha probado en VirtualBox ni hardware físico. No se promete compatibilidad
universal. Esta versión solo usa un HBA y expone hasta cuatro discos combinados
IDE/SATA. No soporta ATAPI por AHCI, NVMe, port multipliers, hotplug, NCQ,
recuperación tras fallo, direcciones DMA >4 GiB ni sectores lógicos 4Kn.
Depende de que firmware haya inicializado el enlace SATA. Las esperas tienen
límites de iteraciones, no plazos calibrados por reloj.

Pruebas:
    bash build.sh
    QEMU_EXTRA_ARGS="-m 256" python3 tools/test_ahci.py
    QEMU_EXTRA_ARGS="-m 256" AHCI_TEST_PORT=sata.5 python3 tools/test_ahci.py
    QEMU_EXTRA_ARGS="-m 256" AHCI_TEST_CONTROLLER=" -machine q35" AHCI_TEST_PORT=ide.0 python3 tools/test_ahci.py
    QEMU_EXTRA_ARGS="-m 256" python3 tools/test_ahci_install.py
    QEMU_EXTRA_ARGS="-m 256" python3 tools/test_ahci_errors.py
    QEMU_EXTRA_ARGS="-m 256" python3 tools/test_08.py

Referencia: Intel Serial ATA AHCI 1.3.1
https://www.intel.com/content/dam/www/public/us/en/documents/technical-specifications/serial-ata-ahci-spec-rev1-3-1.pdf
