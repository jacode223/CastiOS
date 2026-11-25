# CastiOS i386: camino a 1.0

Esta es una compilacion de desarrollo, no una version estable certificada. El kernel sigue identificandose como CastiOS 0.36; el archivo 1.0 se refiere al objetivo de estabilizacion, no a un lanzamiento terminado.

Cambio: el vector x86 #DE atiende divisiones fallidas de tareas CPL3 mediante la ruta de terminacion de tareas. En CPL0 se conserva la parada del kernel. `tools/test_demand_isolation.py` comprueba division entre cero en primer plano y en segundo plano, aislamiento de paginas, recuperacion de shell y paginas liberadas.

`make test` compila y ejecuta la bateria i386 seleccionada en `tools/test_i386_candidate.py`: pruebas de metadatos, aislamiento, syscalls, Castic, PE32 y teclado/raton HID. No equivale a verificar estabilidad en todos los equipos. Algunas pruebas antiguas bajo tools no forman parte de esta bateria y se refieren a versiones o comandos previos.

Comprobado en QEMU: arranque, programa Castic, manejo #DE y de otros fallos CPL3, paginas, syscalls, datos de PE32 sinteticos, teclado y raton EHCI, y prueba de seleccion de metadatos de disco simulando cortes. La prueba de metadatos se ejecuta en el host, no reproduce un corte electrico real. La prueba de entrada USB combinada con almacenamiento no pudo ejecutarse en el entorno por faltar mkfs.fat. No se ha probado esta version en el Amilo ni otros equipos fisicos.

Pendiente antes de considerar un lanzamiento estable: pruebas en equipos fisicos (incluido video, disco, USB y recuperacion), inyeccion de fallos de E/S y cortes de energia, auditoria de seguridad y compatibilidad de controladores, correccion de pruebas antiguas y definicion de una matriz de hardware. PE32 solo inspecciona un archivo de hasta 1 MiB; no resuelve todas las dependencias ni ejecuta apps Windows. USB HID es EHCI experimental, limitado a un teclado y un raton compatibles, sin hubs ni xHCI. Los resultados actuales no avalan usarlo para datos importantes.
