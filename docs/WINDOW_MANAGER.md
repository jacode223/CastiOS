# CastiOS WM 0.35

Tres ventanas integradas: Archivos, Procesos y Sistema. Cada una conserva
coordenadas, tamaño, carpeta, seleccion, desplazamiento y vista previa.
Clic, Ctrl-N o barra de tareas cambia el foco. Ctrl-N omite minimizadas.
Ctrl-W o X cierra; Ctrl-Y o _ minimiza. Ctrl-R restaura la ultima minimizada;
el boton de la barra tambien restaura, o minimiza si ya esta enfocada.
Ctrl-E o + maximiza y recupera la geometria normal. WASD mueve ventanas
normales; arrastra el titulo con mouse PS/2. Ctrl-Z agranda y Ctrl-X reduce;
la esquina inferior derecha permite redimensionar con el raton.

Tab abre Inicio. Esc cierra menu, vista previa o ventana; sin foco sale.
Ctrl-Q sale directamente y conserva la disposicion en RAM al volver a
`desktop`, durante el mismo arranque. No hay guardado de disposicion en disco.
Terminal tambien vuelve a la shell. Minimo 630x430, maximo 960x484; las
ventanas quedan entre la cabecera y la barra. Maximizar no cambia las apps.
Archivos muestra mas filas al agrandar; la vista previa sigue limitada a
600 bytes. Las carpetas o vistas previas borradas desde la shell se revisan
al volver al escritorio para evitar reusar referencias invalidas.

Modulos en src/extensions/wm: types.h define estado; windows.h gestiona
foco, geometria y ciclo de vida; apps.h dibuja contenido; compositor.h dibuja
en orden y guarda 672 bytes bajo el cursor; input.h procesa eventos.
Movimiento simple del cursor restaura solo su rectangulo anterior y dibuja
el nuevo. Abrir, mover o cambiar tamaño recompone el escritorio completo.
Los modulos se compilan en CPL0; no son plugins ni aplicaciones aisladas.

QEMU: test_wm_controls.py verifica minimizar, restaurar, maximizar, tamaño,
entrada/salida de sesion, atajos, movimiento parcial del cursor y arrastre.
test_wm.py y test_mouse.py comprueban foco, carpeta y raton PS/2.
