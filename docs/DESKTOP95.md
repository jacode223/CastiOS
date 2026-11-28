# CastiDesk 95 (experimental, i386)

Un escritorio pequeño inspirado en Windows 95, escrito en Castic.
Incluye fondo verde azulado, barra de tareas, Inicio, icono Mi PC,
ventana de información con botón X y un cursor rectangular blanco.
Mi PC abre información: todavía no es un explorador de archivos.

## Ejecutarlo

Arranca la ISO nueva. En una raíz Live nueva o instalación nueva:

```text
castic /desk.cas /desk.app
exec /desk.app
```

Si ya existe desk.app, compila con otro nombre, por ejemplo desk2.app.
El compilador evita sobrescribir archivos. El fuente se encuentra en
examples/castic/desktop.cas en el repositorio y en /desk.cas en el sistema.

- Clic en Inicio o tecla `s`: abrir/cerrar el menú.
- Clic en Mi PC o tecla `1`: abrir información.
- Clic en X o tecla `c`: cerrar la ventana.
- Clic en Salir, `q`, `Q` o Escape: volver a la shell; no apaga el PC.

## Cambiar su aspecto

Las variables del principio controlan colores y estado:

```c
int desktop_color = 32896;
int panel_color = 12632256;
int title_color = 128;
int window_open = 1;
```

Colores: RGB decimal = rojo * 65536 + verde * 256 + azul.
Posiciones: x + y * 65536. Tamaños: ancho + alto * 65536.
Calcula estas expresiones antes de poner el literal en Castic.
La posición y tamaño base de ventana/barra tienen nombres; los bordes,
etiquetas y áreas de clic mantienen coordenadas explícitas en el dibujo.
Si mueves un control, cambia también sus bordes, textos y comprobaciones
mouse_x/mouse_y. No hay distribución automática ni ventanas arrastrables.

## Variables con nombre

El compilador dentro de esta ISO admite identificadores de 1 a 31 caracteres,
con letras ASCII, guion bajo y dígitos (no al principio). Distingue mayúsculas.
Decláralos con int antes de usarlos. Se admiten comentarios // hasta fin de línea.
Ejemplo:

```c
int counter = 0;
while (counter < 3) { counter += 1; }
return counter;
```

Máximo 26 posiciones de variables compartidas, sin ámbitos locales.
Las letras antiguas siguen funcionando. Con use se reservan posiciones
para los parámetros tradicionales de las bibliotecas (a,p,s,c,t,k,x,y,v).
Usa nombres distintos para funciones y variables. Las bibliotecas importadas
siguen usando sus parámetros de una letra; esta ampliación normaliza el
archivo principal. No convierte Castic en un compilador de C completo.
Fuente máximo 8000 bytes; código AX05 máximo 4000 bytes.

## Compatibilidad y límites

Necesita el kernel y módulo /boot/zzcastic.bin incluidos en esta ISO: copiar
solo desk.cas a una versión vieja no añade el soporte de nombres.
Una actualización que solo cambia el kernel no instala el módulo ni cambia
la configuración GRUB antigua. Prueba esta ISO Live; no reinstales tu disco
para probar el escritorio. Tus fuentes existentes no se reemplazan al arrancar.

Interfaz fija en los primeros 960×600 píxeles de un framebuffer 1024×768.
Ratón PS/2; no se ha validado USB HID ni hardware real para esta entrega.
Redibuja al recibir eventos y espera bloqueado entre ellos. No tiene doble
buffer, ventanas múltiples, reloj, lanzamiento de otras apps ni arrastre.

La syscall i386 25 añade selector EBX=4: EAX=x | (y << 16).
Devuelve -19 si falta el ratón. Los selectores 0..3 no cambian; >4 da -22.
La syscall 26 espera teclado/ratón en primer plano. Las apps siguen en CPL3.

## Verificación

Se probaron compilación real y ejecución en QEMU, nombres y bucles,
Inicio, cerrar ventana, clic para reabrir, salida y compatibilidad con widgets.
El instalador se prueba exclusivamente sobre imágenes temporales de QEMU.
