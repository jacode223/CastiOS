# Recuperación de CastiOS 0.25

En un arranque de prueba A/B, el kernel selecciona **Estable** para el próximo reinicio después de inicializar el controlador de disco y **antes** de montar HSFS. Así, una corrupción de ambos espejos de HSFS no deja a Nuevo seleccionado. Si el montaje falla, CastiOS inicia su sistema temporal en RAM y no escribe en el HSFS inválido. En una sesión candidata que funciona, `castctl kaccept` vuelve a seleccionar Nuevo.

Si Nuevo no llega a inicializar el disco, elige **CastiOS estable** en el menú de GRUB. Si GRUB o el propio disco de arranque fallan, necesitas arrancar desde otra imagen o recuperar una copia externa. CastiOS no tiene watchdog físico ni repara por sí solo un dispositivo averiado.

Los fallos de aplicaciones AX05 en CPL3 terminan esa tarea y liberan sus páginas; los servicios y drivers que siguen en CPL0 aún pueden detener el kernel si contienen un fallo. Los USB externos se montan FAT32 en solo lectura; `castctl usbscan` tiene esperas acotadas y retira montajes obsoletos, pero no aísla el driver EHCI en un proceso. Las escrituras HSFS usan dos copias de metadatos y vaciado de caché, pero los datos de archivos grandes no están duplicados. Mantén copias externas de lo importante.

La prueba `tools/test_early_recovery.py` daña deliberadamente **ambas** copias HSFS en una copia del HDD, inicia Nuevo, comprueba el retorno a Estable y verifica que el contenido dañado no ha sido sobrescrito. El conjunto de pruebas de actualizaciones, procesos, USB y cortes de escritura está en `tools/test_internal_update.py`, `test_multitask.py`, `test_usb_lifecycle.py` y `test_hsfs_commit.py`.
