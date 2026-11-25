# Configuración desde CastiOS 0.17

El fichero HSFS `/system.cfg` guarda opciones del núcleo que se pueden
modificar dentro del sistema. Las dos entradas actuales son `color=cyan`,
`green` o `white`, y `prompt=Texto` (1 a 23 caracteres ASCII imprimibles).

```text
castctl kshow
castctl kset color green
castctl kset prompt Casti>
cat /system.cfg
nano /system.cfg
castctl kreload
```

`kset` valida y guarda el archivo, aplica el cambio en caliente y persiste
en HSFS. El arranque vuelve a leerlo. Si `nano` introduce contenido inválido,
`kreload` lo rechaza y conserva los ajustes activos. En una sesión sin disco
persistente, `kset` se rechaza. El disco usa la sincronización habitual de
HSFS, que no protege contra todos los cortes de alimentación.

Esto modifica configuración del kernel y permite seguir editando programas
Speed, fuentes NASM y drivers MiniDRV desde la shell. **No recompila ni
sustituye instrucciones del núcleo en caliente**. El kernel aún mezcla NASM
y C; su reconstrucción completa usa GCC/ld y el anfitrión con la VM apagada:
`python3 tools/update_kernel.py VIEJO.img NUEVO.img`. Sigue pendiente portar
esas herramientas o crear un cargador seguro de módulos verificados.
