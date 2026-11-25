# Recompilar un candidato de kernel en CastiOS 0.20

Ahora puedes aplicar el candidato desde CastiOS con `castctl kapply
kernel.img`; consulta [ACTUALIZACIONES.md](ACTUALIZACIONES.md). El flujo
del anfitrión descrito más abajo es una alternativa para probar otra imagen
de disco con la VM apagada.

La imagen `CastiOS-hdd.img` contiene el árbol NASM editable en `/src`, las
guías de `/docs/on_disk` y los binarios auxiliares precompilados de `/build`.
Arranca esta imagen con al menos 200 MiB de RAM. Puedes editar un módulo
pequeño, por ejemplo `nano /src/process.asm`, y después ejecutar:

```text
castctl kbuild
```

La compilación usa NASM dentro de CastiOS y publica `/kernel.img` solo si
termina sin errores. **No escribe el sector de arranque ni activa el
candidato**. Los fuentes editados permanecen aunque la compilación falle.
El editor `nano` admite hasta 8000 bytes por archivo; `kernel.asm` supera
ese límite, pero muchos módulos incluidos son más pequeños. Los fuentes
del componente C y los binarios de GRUB aún no se reconstruyen dentro del
sistema: `/build/nasm_runtime.bin` y `/build/hddboot.bin` son los de la
entrega actual.

Con la máquina virtual **apagada**, desde el anfitrión y el directorio del
proyecto extraído de `CastiOS-fuentes.zip`:

```sh
python3 tools/apply_kernel_candidate.py VIEJO.img NUEVO.img --candidate kernel.img
```

La herramienta exige que `NUEVO.img` no exista; conserva `VIEJO.img`, lee
`/kernel.img` del HSFS (`--candidate kernel.img`), valida la cabecera Multiboot y el límite de carga,
crea una ISO GRUB nueva sin modificar el disco viejo, arranca una copia en
QEMU y comprueba la shell, `uname` y una guía. Solo entonces publica el
disco nuevo. Requiere `grub-file`, `xorriso` y `qemu-system-i386` en el
anfitrión. Conecta `NUEVO.img` en VirtualBox y arranca. Si falla después,
apaga la VM y vuelve a conectar `VIEJO.img`.

Este procedimiento detecta errores de ensamblado, cabeceras rotas y fallos
de arranque reproducibles en QEMU. **No puede demostrar que código arbitrario
no vaya a bloquear el kernel después, ni garantiza seguridad en hardware
diferente**. El flujo externo requiere cambio de disco; la vía `kapply`
actualiza desde dentro. Ninguna de las dos ofrece autorreversión si el
kernel falla después del arranque. Para cambios
en C o GRUB, reconstruye desde el anfitrión con `build.sh` y usa
`tools/update_kernel.py` sobre una copia apagada.

Para agregar el árbol editable a otra imagen HDD ya creada (con la VM
apagada) sin pisar los archivos del usuario:

```sh
python3 tools/seed_kernel_sources.py OTRA.img
```
