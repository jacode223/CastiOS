# Inspeccion PE32 y recursos: version experimental

`castctl peinfo /ruta/archivo.exe` inspecciona un unico archivo PE32 x86 de hasta 1 MiB, incluyendo DLL que usen el mismo formato. Muestra las DLL y funciones importadas sujetas a los limites existentes y ahora el numero de tipos en la raiz del directorio de recursos y su tamano. Rechaza cabeceras y directorios de recursos fuera de limites. No abre ni ejecuta el archivo.

El analisis de recursos solo valida el directorio raiz: no enumera ni valida el arbol completo, sus nombres, idiomas o datos. No garantiza que cada entrada o dependencia sea valida. No resuelve ni busca DLL en el disco, no explora directorios recursivamente, y no detecta dependencias dinamicas, delay imports, manifiestos, COM, registros o todos los recursos externos. No se admiten PE32+ x64 ni archivos mayores de 1 MiB. No se ha portado Win32 y no se pueden ejecutar aplicaciones Windows mediante este comando.

No es un producto estable ni un escaner de seguridad. Los formatos reales son complejos y deben probarse con una gran coleccion y archivos corruptos. `tools/test_pe32.py` prueba muestras sinteticas, limites y manejo de errores en QEMU; no equivale a validar todos los ejecutables de Windows.
