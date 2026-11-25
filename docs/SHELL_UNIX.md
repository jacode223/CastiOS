# Shell de CastiOS 0.16

La tabla publica y el autocompletado usan nombres Unix: `desktop`, `help`, `ls`,
`cat`, `head`, `cd`, `pwd`, `mkdir`, `touch`, `rm`, `cp`, `mv`,
`stat`, `mount`, `umount`, `sync`, `echo`, `clear`, `uname`,
`whoami`, `uptime`, `date`, `nano`, `ps`, `wait`, `kill`, `bg`,
`exec`, `execall`, `nasm`, `reboot` y `halt`.

Las operaciones particulares del kernel viven en `castctl`. Ejecuta
`castctl help` para la lista: incluye `write`, `append`, `fsinfo`,
`raminfo`, `disks`, `usbscan`, `drivers`, `install`, `speed` y
`font`. Los nombres viejos como `dir`, `type`, `copy`, `version`,
`run`, `run2`, `waitbg` y `write` ya no son comandos directos.

Ejemplo:

```text
castctl write /nota.txt Hola
cp /nota.txt /copia.txt
mv /copia.txt /nueva.txt
cat /nueva.txt
bg /app.app
ps
kill 1
wait 1
```

El `cp` entre archivos locales admite hasta 1 MiB en esta version y
requiere 200 MiB de RAM para el runtime C. Al importar desde FAT32 puede
copiar archivos de hasta 100 MiB a HSFS en bloques de 1,44 MiB; FAT32 sigue
siendo de solo lectura. `mv` renombra/mueve archivos de HSFS, sin sobrescribir
el destino. No hay tuberias, globbing, variables de entorno, redireccion,
procesos POSIX ni compatibilidad con scripts sh. La interfaz se parece a Unix
en comandos y rutas, pero no es un shell POSIX.

`kill PID` detiene una tarea AX05 de fondo activa o dormida, libera sus
recursos y deja resultado 143 visible en `ps`. `wait PID` recoge su resultado
y libera la ranura; `wait` sin argumentos espera todas las restantes. Un
nuevo `bg` recibe otro PID aunque reutilice esa ranura. Máximo cuatro tareas
de fondo simultáneas. No hay señales POSIX ni PIDs globales del sistema.

`desktop` abre el escritorio RGB32. Tab muestra Inicio; las flechas y Enter
o el ratón PS/2 abren Terminal, Archivos, Procesos y Sistema. Archivos lista
HSFS, permite entrar en carpetas, volver con Backspace y previsualizar texto.
Procesos muestra PID y estado de tareas de fondo. Esc cierra la ventana y
después sale del escritorio. Terminal vuelve a la shell; FAT32 se consulta
con `mount` y `ls` desde allí. En modo VGA texto se requiere framebuffer.
