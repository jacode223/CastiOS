# API gráfica Castic i386

Esta revisión permite variables definidas como argumentos de syscall.
Los enteros de posición se calculan como x + y*65536 y los de tamaño como
ancho + alto*65536. El color es RGB de 24 bits.

La biblioteca se carga con use desk;. Define antes de llamar las variables
que necesita cada función.

| Función | Entradas | Resultado |
| --- | --- | --- |
| r() | p posición, s tamaño, c color | a, estado del rectángulo |
| t() | t texto ASCII empaquetado de 1–4 bytes, p posición, c color | a |
| b() | p posición, s tamaño, c fondo, t etiqueta empaquetada | a |
| f() | Ninguna | Fondo fijo de 1024 × 768, estado en a |
| k() | Ninguna | Tecla en a |
| w(), h() | Ninguna | Ancho en x, alto en y |

b dibuja un rectángulo y etiqueta blanca desplazada 8 píxeles.
El programa gestiona la activación por teclado. La biblioteca todavía no
implementa clics ni ventanas superpuestas. p se restaura después de b.

## Ejemplo

```c
use desk;
int a = 0;
int p = 655370;
int s = 2621540;
int c = 255;
r();
syscall(23,'Hola',p,16777215,a);
k();
return a;
```

```text
castic /ejemplo.cas /ejemplo.app
exec /ejemplo.app
```

El escritorio está en /desk.cas y la biblioteca en /lib/desk.cas.
Compila con castic /desk.cas /nuevo.app y ejecuta exec /nuevo.app.
1 muestra información, 2 muestra hda/hdb si están disponibles, Q o Escape sale.
El código se instala en nuevas instalaciones y en el entorno Live temporal.
Una instalación existente conserva sus archivos y necesita copiar los nuevos
fuentes y biblioteca, además de actualizar el kernel.

Los programas AX05 tienen un límite de código de 4000 bytes. Las funciones se
expanden en cada llamada. Las coordenadas, colores y tamaños están sujetos
a las validaciones del kernel. No hay transparencia ni doble buffer.

Las syscalls 21 y 23 siguen siendo las primitivas de dibujo.
Esta revisión también corrige las llamadas a funciones dentro de if/while
y conserva los valores de entrada cuando la variable de resultado coincide.

## Ratón y eventos de entrada

Se añaden las syscalls 25 y 26 al ABI i386.

| Llamada | Resultado EAX |
| --- | --- |
| syscall(25,0,0,0,x) | Posición X del ratón |
| syscall(25,1,0,0,y) | Posición Y del ratón |
| syscall(25,2,0,0,v) | Botones, bits 0 izquierdo, 1 derecho, 2 central |
| syscall(25,3,0,0,a) | Disponibilidad PS/2, 1 presente o 0 ausente |
| syscall(26,0,0,0,k) | Espera teclado o evento de ratón en primer plano |

La 25 devuelve -22 para selectores mayores que 3 y -19 si se pide estado
sin ratón PS/2 disponible. Las consultas no consumen eventos.
X, Y y botones se consultan por separado y pueden cambiar entre llamadas.
El driver actual limita las coordenadas a X=0..959 e Y=0..599.
Todavía no se dibuja un cursor automáticamente.

La 26 devuelve 137 al pulsar el botón izquierdo, 138 al recibir otros
paquetes de ratón, incluidos movimiento o liberación, o el código habitual
de teclado. Los eventos pueden agruparse. No forman una cola con una
instantánea de cada clic. Consulta 25 para obtener el estado actual.
Con multitarea activa devuelve -16. Al salir restaura el modo de teclado
normal. La syscall 22 conserva su comportamiento anterior.

La biblioteca incorpora m(), que escribe x, y, v, y e(), que espera un
evento y lo guarda en k. Declara esas variables antes de usar las funciones
dentro de un bucle. El ejemplo examples/castic/mouse.cas responde a clics
y sale con q o Escape. Los botones dibujados siguen necesitando que la
aplicación compruebe las coordenadas y ejecute la acción correspondiente.

La prueba tools/test_mouse_syscalls.py usa movimiento y botones PS/2 de
QEMU y comprueba llamadas desde aplicaciones Castic en CPL3.
El soporte USB depende del driver HID existente y requiere validación aparte.
