# Castic 0.1 en CastiOS i386

`castic` compila código Castic directamente dentro de la rama i386. El compilador forma parte del kernel y genera instrucciones x86 de 32 bits en un archivo AX05. El ejecutable se valida con el validador AX05 y se ejecuta en CPL3 con memoria privada y syscalls. Esta versión no incluye Neovim: `nano` es el editor propio existente del proyecto.

Ejemplo con almacenamiento montado (o en RAM en modo live):

```text
castctl write /hola.cas print hola mundo
castctl append /hola.cas print segunda linea
castic /hola.cas /hola.app
exec /hola.app
```

También puedes crear y editar `/hola.cas` con `nano /hola.cas` (Ctrl-O guarda y Ctrl-X sale). Si no hay almacenamiento persistente montado, los archivos están solo en RAM y se perderán al apagar.

## Sintaxis y límites

`print TEXTO` escribe texto; también se admiten las instrucciones de variables descritas abajo. Separa las instrucciones con salto de línea o punto y coma; cada `print` añade un salto de línea. El texto debe contener ASCII imprimible y tener entre 1 y 128 bytes. No se pueden incluir `;` ni saltos de línea dentro del texto. Admite fuente de hasta 8000 bytes en un archivo de texto normal y produce AX05 que cabe en el límite de código validado. Si la sintaxis o el tamaño son inválidos, no crea el destino. Para evitar pérdida de datos, rechaza un destino que ya exista. El escritorio de ejemplo usa funciones, condiciones y lectura de teclado.

Las syscalls y ABI i386 son independientes de las de x64. Los archivos `.app` generados son AX05, no ejecutables ELF ni programas de Linux. La escritura de `print` utiliza la syscall de consola 5, a través de una página de datos de usuario asignada por demanda. El compilador valida todo antes de guardar. Si el sistema de archivos indica fallo de E/S durante la publicación, hay que recuperar el volumen antes de confiar en la escritura.

En QEMU: `python3 tools/test_castic_i386_vm.py` después de `make`. El test comprueba salida real, varios comandos, errores, no sobrescritura y persistencia tras reiniciar la máquina virtual.

## Variables y operaciones experimentales

Además de `print`, se admiten variables de una letra minúscula (`a` a `z`), con números enteros sin signo de 32 bits:

```text
let a 7
add a 5
sub a 3
mul a 4
div a 3
return a
```

La variable se almacena en la memoria privada del proceso y las operaciones se ejecutan al iniciar el AX05. `return` debe ser la última instrucción y devuelve el valor como código EAX que muestra `exec`. Suma, resta y multiplicación usan aritmética de 32 bits con desbordamiento modular. La división es entera sin signo y el compilador rechaza divisores cero. El compilador rechaza variables no definidas y literales fuera de rango. No hay expresiones generales ni impresión de números todavía.

## Sintaxis tipo C y syscalls

Se permiten declaraciones como `int a = 7;` y operaciones sobre variables de una letra como `a += 5;`, `a -= 2;`, `a *= 3;` y `a /= 2;` (espacios obligatorios). Cada sentencia termina en punto y coma o salto de linea. `int` aqui representa un entero sin signo de 32 bits, no el tipo C estandar. Se mantienen `let`, `add`, `sub`, `mul`, `div`, `print` y `return`.

`syscall(numero, ebx, ecx, edx, variable);` ejecuta `int 0x80` en CPL3 y guarda EAX en la variable indicada, que queda definida. Los cuatro primeros argumentos admiten enteros decimales sin signo o entre uno y cuatro caracteres ASCII imprimibles entre comillas simples, empaquetados con el primero en el byte bajo; la variable de resultado es una letra minuscula. Ejemplo:

```
syscall(3,0,0,0,p);
return p;
```

La syscall 3 devuelve el PID. Los errores negativos se conservan como bits de 32 bits; la shell los muestra como enteros sin signo (por ejemplo -14 como 4294967282). Syscalls que requieran punteros, permisos o archivos mantienen sus validaciones y restricciones; el compilador no aporta automaticamente buffers ni permisos. Algunas llamadas cambian el control de flujo, como exit.

El compilador implementa el subconjunto de Castic descrito aquí. Las variables tienen una letra y las operaciones admitidas se describen arriba. La division es entera sin signo. `return` debe ser la ultima sentencia. El compilador sigue ejecutandose en el kernel; el programa resultante es AX05 en CPL3. Ver `docs/on_disk/SYSCALL.TXT` para el ABI.

## Funciones sin parametros (expansion en compilacion)

```text
fn f { a += 2; }
int a = 3;
f();
f();
return a;
```

Este programa devuelve 7. Cada nombre de funcion es una letra minuscula y la definicion debe aparecer antes de la llamada. El compilador incorpora el cuerpo en cada llamada; no se genera una llamada de maquina ni una pila de funciones. Las variables son compartidas, no existen argumentos ni valores de retorno propios de la funcion. La sentencia `return` solo puede aparecer en el programa principal, al final. No se permiten llamadas dentro de funciones, recursividad, llaves anidadas ni llaves en textos de `print`. El cuerpo se valida cuando se expande en una llamada; una funcion sin usar no se analiza completamente. Las expansiones cuentan para el limite de tamano AX05. Una llamada puede contener `print`, variables, operaciones o `syscall`, sujeto a sus restricciones normales.

## Condiciones y bucles (i386)

```
int a = 0;
while (a < 5) {
    a += 1;
}
if (a == 5) {
    a += 2;
}
return a;
```

La condicion acepta una variable de una letra, un operador (`==`, `!=`, `<`,
`<=`, `>` o `>=`) y un literal decimal sin signo de 32 bits. Se requieren
parentesis y llaves. Los bloques se pueden anidar hasta ocho niveles. Declare
todas las variables antes de entrar en un bloque; si usa una syscall en un
bloque, su variable de resultado debe estar previamente declarada. `return`
solo se permite fuera de bloques, al final. Aun no hay `else`, `break`,
comparacion entre variables, expresiones generales ni comprobacion de
terminacion: un while puede ser infinito. Las definiciones o cuerpos de
funcion no aceptan bloques; se pueden llamar funciones ya definidas desde
un bloque. Las comparaciones son sin signo. AX05 valida que los saltos
apunten al principio de una instruccion dentro del programa.

## Escritorio y consulta de discos

En una sesión live con la raíz temporal, o en una instalación nueva, el
archivo editable es `/desk.cas`. La directiva `use desk;` carga
`/lib/desk.cas`. Para probar el escritorio desde la terminal:

```text
castic /desk.cas /desk.app
exec /desk.app
```

Las teclas 1, 2 y 3 muestran información, discos y ayuda. Q o Escape cierra
el programa y recupera la terminal. La vista de discos muestra las unidades
con capacidad accesible en los cuatro puestos del controlador de bloques.

```c
syscall(23,'Hola',655370,16777215,a);
syscall(24,0,0,0,b);
```

La primera llamada dibuja texto blanco en (10, 10) con la fuente de 8 × 16.
La segunda consulta cuántos sectores de 512 bytes puede direccionar el
controlador de hda. Los puestos 0 a 3 corresponden a hda hasta hdd. Un
puesto sin disco utilizable devuelve 0. Un índice fuera de rango devuelve
-22. La consulta lee el inventario en memoria.
