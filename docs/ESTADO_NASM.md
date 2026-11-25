# NASM integrado: alcance comprobable

`build/nasm32` se compilo desde el ZIP aportado, como ELF32 i386 estatico con
glibc 2.41. GRUB lo carga como modulo tanto desde CD como desde disco instalado.
El comando `nasm` carga sus segmentos, prepara argc/argv/auxv y TLS, y proporciona
las llamadas i386 que necesita esta compilacion. Se ejecuta en la propia CPU de
la VM: no se invoca un ensamblador del anfitrion ni un kernel Linux.

`src/nasm.asm` conecta el kernel con `src/nasm_runtime.c`. Este ultimo implementa
heap, mapas temporales y la interfaz read/write/seek/stat sobre ASFS4. El kernel
reserva el modulo a 48 MiB, un snapshot ASFS a 64 MiB y el proceso entre 128 y
192 MiB, fuera del asignador habitual de paginas de 16 a 32 MiB.
La configuracion 0.22 usa 200 MiB. Cada invocacion reinicia heap y mapas.

Las escrituras usan un snapshot; solo exit(0), con estructura valida, permite
copiarlo al volumen del kernel y persistirlo. La falta de espacio y los errores
de NASM no publican archivos parciales. Las cadenas de ASFS4 se validan tanto
en el kernel como en las herramientas Python antes de aceptar datos.

No es una implementacion completa de la ABI Linux ni una libc propia. Algunas
llamadas administrativas son operaciones vacias; no hay hilos o senales reales.
Los relojes del adaptador y los bytes de inicializacion de libc son constantes,
no fuentes de tiempo ni de aleatoriedad para aplicaciones. El proceso tiene
privilegios del kernel y no se usa para ejecutar binarios externos arbitrarios.
NASM no se ha probado en hardware real ni con todas sus opciones o formatos.

La shell ejecuta AX05 validado; no carga genericos ELF ni binarios planos. El
ejemplo `app.asm` produce AX05 directamente y respeta su subconjunto x86.
Los drivers de hardware aun se integran al construir el kernel; MiniDRV sigue
siendo un lenguaje de dispositivos virtuales. No se afirma que pueda
reconstruirse o reemplazarse todo el sistema desde dentro en esta version.

Las pruebas reproducibles y resultados estan en `tools/test_08.py`,
`tools/test_08_regression.py` y `docs/VALIDACION_0.8.txt`.
