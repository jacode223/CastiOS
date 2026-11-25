# Compatibilidad Win32: etapa 0.36

`castctl peinfo RUTA.exe` lee un archivo PE32 x86 desde HSFS, RMFS o un
volumen FAT32 montado. Requiere el perfil completo (200 MiB) y por ahora
acepta archivos de hasta 1 MiB. Comprueba firma MZ/PE, arquitectura i386,
cabecera opcional PE32, tabla de secciones, límites de bytes en disco y
directorio de importaciones. Muestra base, RVA de entrada, tamaño de imagen,
subsistema, número de secciones, DLL y hasta 24 símbolos importados. Rechaza
PE32+ de 64 bits y cabeceras malformadas antes de leer punteros fuera del
buffer. El archivo nunca se ejecuta ni se copia a la memoria de procesos.

Esta es una implementación propia basada en el formato público PE/COFF.
No se utiliza código ni material filtrado de Windows XP. El formato PE32
no implica compatibilidad con Windows 10: la mayoría de programas necesitan
DLL, objetos del sistema, llamadas Win32, hilos y una interfaz gráfica que
CastiOS aún no implementa. Tampoco hay WOW64 ni soporte para binarios x64.

Siguiente etapa del kernel: reservar páginas privadas para una imagen PE32,
aplicar protecciones de código/datos, construir la tabla de importaciones
con una lista explícita de funciones Win32 propias y saltar a la entrada
solo en CPL3. Rechazar las importaciones no implementadas con un error
visible. El servicio de ventanas y las syscalls deberán mediar E/S y dibujo;
una aplicación no recibirá acceso directo al framebuffer ni al disco.

`tools/test_pe32.py` genera una imagen sintética y verifica en QEMU la
extracción de `KERNEL32.dll!ExitProcess`, la negativa a ejecutar, el rechazo
de RVAs inválidas y de arquitectura x64, y que la shell sigue operativa.
