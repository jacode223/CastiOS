# Instalación experimental BIOS x86-64

Esta edición solo instala en el disco **IDE primario maestro hda**, con BIOS,
sectores de 512 bytes, soporte LBA y FLUSH, y capacidad mínima de 17 MiB.
AHCI en x64 todavía es de solo lectura y no admite instalación. No instala en
UEFI ni ofrece selección de discos o particiones: el proceso reemplaza el
arranque y el volumen del disco completo. `disks` muestra la capacidad del
IDE hda, o la del AHCI seleccionado después de `ahciscan`. No es un inventario
completo de otros discos.

En VirtualBox crea una VM x86-64 con BIOS, conecta una copia de un disco
vacío como IDE primario maestro y arranca con la ISO x64. En la consola:

```text
disks
install
install hda borrar
```

`install` muestra la advertencia; la última orden confirma y **borra el
contenido lógico del disco elegido**. Retira la ISO y reinicia. El instalador
escribe una imagen de arranque GRUB BIOS y dos tablas HSFS6 desde el offset
16 MiB; escribe el sector de arranque al final. Después `mount`, `ls`,
`echo texto > archivo` y `cat archivo` operan sobre HSFS6. El límite sigue
siendo LBA28 (128 GiB) y no hay escritura de archivos grandes ni carpetas.

Si la instalación se interrumpe, el disco destino puede quedar incompleto;
el instalador no ofrece reversión, reparación de instalaciones anteriores ni
particionado y no debe usarse sobre datos que se quieran conservar. Se ha
verificado con imágenes descartables en QEMU, no con hardware físico.

Alternativa en el anfitrión: `python3 tools/install_x64_image.py disco.img
--size-mib 128` crea un archivo de imagen nuevo. La herramienta no sobrescribe
archivos existentes ni escribe directamente dispositivos de bloque.

`tools/test_install_x64.py` prueba ambos caminos, arranca desde el disco sin
ISO, monta HSFS6 y verifica la persistencia después de otro arranque.
