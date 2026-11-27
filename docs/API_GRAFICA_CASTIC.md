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
