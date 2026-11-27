# Instalador gráfico — CastiOS 0.37-exp1

Versión experimental del 27 de noviembre de 2026. Arquitectura i386, BIOS y framebuffer RGB32 de al menos 1024 × 768. Diseño original inspirado en el asistente de Windows XP; no utiliza código ni recursos de Microsoft.

## Uso

1. Arranca `build/CastiOS.iso` como medio Live.
2. Escribe `install` sin argumentos.
3. Avanza con Enter. Selecciona la unidad con 1–4; se muestran hda–hdd, modelo y capacidad accesible en MiB.
4. Revisa el destino y escribe exactamente `FORMAT hda`, `FORMAT hdb`, etc. No basta con Enter. Un texto incorrecto permanece en la confirmación y no escribe en disco.
5. Espera la copia, vaciado de caché y verificación por lectura. No retires el medio ni apagues el equipo.
6. Si termina correctamente, vuelve a la terminal con Enter, apaga/reinicia y retira la ISO para arrancar desde el disco.

Esc cancela la bienvenida o selección, y vuelve a selección desde la confirmación. Durante la copia no se admite cancelación. La interfaz utiliza teclado; no hay controles de ratón todavía.

La instalación usa el disco completo. Destruye las estructuras de arranque y las particiones previas; no realiza un borrado seguro de todos los sectores. No instala junto a otro sistema ni conserva una instalación anterior. **Nunca utilices install para actualizar archivos conservando datos.**

El modo de terminal sigue disponible con `install hda|hdb|hdc|hdd`, con la misma confirmación y el mismo motor de copia/verificación. En modo VGA utiliza esa variante. En el sistema instalado se solicita arrancar la ISO Live: el módulo de instalación no se copia al disco.

## Validaciones

- La imagen Live debe tener un payload válido, alineado a 512 bytes y de hasta 8 MiB.
- No se instala mientras haya tareas de fondo activas.
- El destino debe estar reconocido, admitir vaciado de caché y tener al menos 48641 sectores accesibles (aproximadamente 23,75 MiB).
- Se comprueban de nuevo los requisitos antes de mutar el sistema de archivos o el disco.
- Toda escritura, flush o lectura fallida interrumpe el proceso. El éxito requiere comparar byte a byte todas las regiones copiadas después del flush.
- Un fallo posterior a la confirmación puede dejar el destino incompleto. La raíz en memoria queda sin persistencia para evitar escrituras automáticas sobre ese destino. Se puede regresar a la terminal.

La verificación detecta errores de copia/lectura en ese momento, pero no garantiza supervivencia ante un corte eléctrico ni la veracidad de la caché de todos los dispositivos. No existe rollback de la instalación destructiva. Los otros discos no se modifican intencionadamente.

## Arquitectura

`src/installer.c` compila como binario independiente mediante `src/installer.ld`. Su cabecera CINS contiene la entrada de ejecución. GRUB lo carga como último módulo de la ISO Live; `memory_modules` valida tamaño y entrada y lo conserva en la región reservada 0x70000–0x80000 antes de mover los otros módulos.

`src/install.asm` sirve de puente entre la shell y el módulo. Expone el ABI interno de framebuffer/teclado/E/S existente, inventario, tamaño del payload y callbacks de selección e inicialización de HSFS5. No se amplía el ABI de syscalls de las aplicaciones. El módulo corre en CPL0 y es código de confianza, no un proceso aislado.

El payload de instalación sigue en 0x800000. El instalador ajusta su `set asmdisk=hdX` al destino seleccionado. La imagen de arranque se escribe desde LBA 0, el volumen HSFS5 desde LBA 32768 y su espejo desde LBA 40960. Las ranuras de kernel y el formato de actualización A/B existente mantienen su disposición.

El progreso se calcula con los sectores efectivamente copiados y verificados, no con una espera artificial. Solo se repinta cuando cambia el porcentaje o la fase. No se reserva un framebuffer adicional ni memoria proporcional al tamaño del disco; la comparación usa un buffer de 512 bytes.

## Construcción

Dependencias: GCC capaz de producir código i386 freestanding, binutils, NASM, Python 3, GRUB i386-pc y xorriso. El árbol incluye `build/nasm32`; si falta, consulta `tools/build_nasm32.sh`.

```sh
make i386
make test-installer
```

La ISO es `build/CastiOS.iso`. La imagen de disco interno `build/installer.iso` no incluye setup.bin. No escribas esa imagen directamente sobre un disco con datos.

## Pruebas y límites

`tools/test_graphical_install.py` automatiza bienvenida, selección, confirmación incorrecta, cancelación sin cambios, instalación en hdb, conservación del disco hda, verificación, arranque con ambos discos conectados y persistencia después de otro arranque. Guarda capturas PPM de las pantallas en build.

`tools/test_installer_errors.py` cubre ausencia de discos, disco pequeño, errores reales de escritura y lectura de verificación inyectados con blkdebug y continuidad de la shell. Las pruebas solo crean imágenes temporales de QEMU.

Se mantienen las pruebas de instalación por terminal. Estas comprobaciones no validan hardware real: Amilo, Compaq, controladoras USB, fallos eléctricos, particionado y UEFI necesitan pruebas o implementación adicionales.
