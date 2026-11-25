# Castic 0.1: lenguaje compilado para CastiOS x64

Castic es un primer lenguaje experimental. El compilador está integrado en el kernel x64, lee un archivo de HSFS6.1 y genera un ejecutable de código máquina x86-64 para el cargador CSH1. El programa resultante corre en CPL3 y usa las syscalls de escritura y salida. El compilador todavía no es una aplicación aislada.

## Primer programa desde CastiOS

Necesitas un volumen HSFS montado en un disco IDE escribible:

```text
mount
echo print hola mundo > /hola.cas
castic /hola.cas /hola.bin
shell run /hola.bin
```

El programa muestra `hola mundo` y termina. Puedes crear código con `echo` o `write6`; el editor de texto de i386 no está disponible en esta rama x64. `castic` no sobrescribe un destino ya existente.

## Sintaxis

Cada instrucción es `print TEXTO`. Las instrucciones se separan por salto de línea o `;`. Por ejemplo, un archivo con:

```text
print primera linea
print segunda linea
```

produce dos líneas de salida. No hay comillas, variables, cálculos, funciones, control de flujo, entrada ni biblioteca estándar en esta versión. Los espacios tras `print` se omiten; `;` y saltos de línea terminan el texto y no se pueden incluir literalmente.

El código fuente puede ocupar hasta 256 bytes; cada texto tiene entre 1 y 119 bytes y el binario completo un máximo de 511 bytes. Si hay un error de sintaxis o se supera el límite, no se crea el destino. No se admite NUL en el código fuente. La salida usa el contenedor simple de shells CSH1 existente (no ELF). El ejecutable tiene una página de código de 4096 bytes, una de datos y una de pila. No hay enlazador, bibliotecas, ejecución en segundo plano ni protección contra procesos que entren en bucle infinito.

AHCI sigue siendo de solo lectura. La creación del código y del binario requiere el backend IDE de escritura. `tools/test_shell_external_vm.py` prueba programas creados dentro del sistema, varias instrucciones, errores y no sobrescritura.
