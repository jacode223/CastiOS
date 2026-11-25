# Crear una shell de usuario en CastiOS x64

La shell externa se guarda en HSFS6.1 y se ejecuta en CPL3 con páginas separadas para código, datos y pila. Al salir o si provoca una excepción, se recupera la consola del kernel. Ejemplo en un disco HSFS ya preparado:

```text
mount
shell new /mi-shell
shell run /mi-shell
help
exit
```

`shell new` crea una copia de la plantilla y no sobrescribe un archivo existente. La plantilla ofrece `help` y `exit`. Se puede ejecutar otra vez después de montar el volumen. Actualmente la escritura HSFS requiere un disco IDE compatible; el backend AHCI sigue siendo de solo lectura.

Para crear un comportamiento nuevo, modifica `examples/shell64/shell.asm` en otro equipo, compílalo con NASM y copia el binario al volumen con `tools/hsfs6.py`:

```sh
nasm -f bin examples/shell64/shell.asm -o mi-shell.bin
python3 tools/hsfs6.py put disco.img /mi-shell mi-shell.bin
```

Usa un archivo HSFS con el binario y arráncalo con `shell run /ruta`. La plantilla usa `int 0x80`: syscall 1 escribe texto, 31 obtiene una tecla sin bloquear y 0 sale. La 31 devuelve -11 cuando no hay tecla y -16 durante multitarea; se sondea PS/2, no USB. El ejecutable es un binario plano x86-64 con origen `0x40000000`, comienza por `EB 04` seguido de `CSH1` y ocupa como máximo 4096 bytes. Datos: `0x40002000` (4096 bytes); pila: `0x40004000` a `0x40005000`. El registro de retorno es RAX. No es ELF ni un ABI de Linux.

Limitaciones: no existe todavía un ensamblador/editor x64 integrado, así que `shell new` crea la plantilla y el código personalizado debe compilarse fuera de CastiOS. El cargador de shells siempre inicia una tarea de primer plano con la identidad root experimental; no hay autenticación, permisos de ejecución completos, stdin bloqueante, trabajos en segundo plano, pipelines ni ejecución de comandos de la shell clásica desde la shell externa. La syscall 31 hace sondeo y un programa que espera en bucle consume CPU. `rescue` no proporciona una frontera de seguridad. No existe todavía una interrupción universal para detener una shell que entre en un bucle infinito. El archivo no está verificado criptográficamente y el formato no es un sistema de paquetes.

Prueba automática en QEMU: `python3 tools/test_shell_external_vm.py` después de compilar la ISO x64. Se comprueban creación, rechazo de sobrescritura, formato inválido, recuperación de fallo, teclado, salida y remontaje.
