# AHCI SATA para CastiOS x86-64

El módulo `src/x64/ahci.asm` adapta el driver propio de CastiOS i386
(`src/drivers/ahci.asm`). No incluye código del kernel Linux ni es un port
binario de sus drivers. La implementación de Linux requiere sus subsistemas
PCI, libata, DMA y gestión de interrupciones. Referencias públicas:
https://github.com/torvalds/linux/blob/master/drivers/ata/ahci.c y
https://github.com/torvalds/linux/blob/master/drivers/ata/libahci.c.

Ejecuta `ahciscan` para seleccionar el primer controlador PCI AHCI y el
primer puerto SATA detectado; `mount`, `ls`, `cat` y `stat` acceden al
volumen HSFS6. El controlador usa una página física como búfer DMA, comandos
serializados y esperas acotadas. Si ocurre un timeout o error, bloquea el
puerto y conserva la página DMA; no intenta reutilizarla. Acepta MMIO por
encima de 3 GiB y por debajo de 4 GiB, y sectores de 512 bytes. Solo lectura:
un intento de escritura falla antes de emitir un comando de escritura.

El acceso HSFS6 todavía aplica el límite LBA28 de 128 GiB. No hay detección
automática al arrancar, selección entre varios discos, escritura AHCI,
hotplug, NCQ, xHCI ni garantías con hardware físico. La rama i386 tiene su
controlador propio. `tools/test_ahci64.py` verifica con QEMU/ICH9-AHCI la
detección, lectura de archivo desde la shell y syscall CPL3, rechazo de
escritura y que la imagen completa no cambie.
