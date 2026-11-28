# Biblioteca de interfaz Castic

Incluida en /lib/desk.cas. Carga con use desk;.
La nueva versión del compilador admite hasta 26 funciones con nombres de
1 a 31 letras minúsculas. Se conservan las funciones antiguas de una letra.

## Parámetros

Los parámetros se asignan a variables compartidas antes de llamar una función.

| Variable | Uso |
| --- | --- |
| p | x + y * 65536 |
| s | ancho + alto * 65536 |
| c | Color RGB de 24 bits |
| t | De uno a cuatro caracteres ASCII empaquetados en un uint32 |
| a | Resultado de dibujo, 0 indica éxito |
| k | Código devuelto por event() |
| x, y, v | Estado escrito por mouse(), posición y botones |

Los cálculos de empaquetado se hacen antes de escribir el literal en el fuente.

## Funciones

- window() pinta un fondo de 1024 × 768 con el color c.
- frame() dibuja un panel con p, s y c.
- label() dibuja el texto t en p con color c.
- button() dibuja un panel con etiqueta blanca y margen de 8 píxeles.
- event() espera teclado o ratón y escribe k.
- mouse() consulta las coordenadas y botones en x, y, v.

Estas funciones ofrecen primitivas con nombres familiares de interfaces como
Tkinter. Los botones necesitan que el programa compruebe el clic y las
coordenadas. Todavía no hay objetos de widget, callbacks, pack/grid, campos
de entrada, cursor automático ni texto largo. La aplicación controla el bucle.

## Ejemplo mínimo

~~~c
use desk;
int a = 0;
int p = 655370;
int s = 3145908;
int c = 1471336;
int t = 1634496328;
int k = 0;
button();
event();
return k;
~~~

t contiene el texto «Hola». Puedes calcular un valor desde Python con
int.from_bytes(b"Hola", "little").

~~~text
castic /ejemplo.cas /ejemplo.app
exec /ejemplo.app
~~~

examples/castic/widgets.cas incluye un panel, un botón y detección de clic.
Sale con q o Escape. La prueba usa ratón PS/2 en QEMU.

Para usar la biblioteca en una instalación existente necesitas el kernel nuevo
y actualizar /lib/desk.cas. El comando update conserva los archivos de usuario.
Las sesiones Live nuevas y las instalaciones nuevas reciben la biblioteca incluida.

Las funciones se expanden durante la compilación y los programas siguen
limitados a 4000 bytes de código AX05. No hay parámetros formales ni llamadas
anidadas dentro de funciones.
