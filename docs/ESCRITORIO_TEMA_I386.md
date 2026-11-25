# Escritorio y discos en CastiOS i386

Comandos publicos:

- `disks` enumera los discos y controladoras detectados.
- `install hda` instala en el disco seleccionado. La instalacion borra datos del disco: el comando solicita escribir exactamente `FORMAT hda`. Sustituye `hda` por el dispositivo elegido y comprueba el modelo y capacidad en `disks` antes de confirmar. Usa una maquina virtual o un disco de pruebas.
- `desktop` abre el escritorio si hay framebuffer RGB32 compatible.

El tema se personaliza en `src/extensions/wm/theme.h`: modifica los valores `0xRRGGBB`, por ejemplo `WM_COLOR_BACKGROUND` para el fondo o `WM_COLOR_ACCENT` para el color destacado. Despues recompila con `make`. El tema es codigo de compilacion, no se carga de un archivo de configuracion en ejecucion. Las ventanas, botones y controles estan en los demas archivos de `src/extensions/wm/`.

El escritorio conserva los controles de teclado y raton anteriores: Tab abre Inicio, las flechas cambian de opcion, Enter abre, Ctrl-Q sale, Ctrl-N cambia de ventana, Ctrl-W cierra, Ctrl-Y minimiza, Ctrl-R restaura y Ctrl-E maximiza. El soporte de raton USB depende de las limitaciones EHCI indicadas en USB_HID_I386.md. Estas funciones son experimentales en hardware real.
