# CastiPS 0.1: informe de entrega

Fuente base: CastiOS HSFS 6.1, sin sustituir los componentes originales de 32 bits.

## Cambios

- `src/x64/castips_defs.inc`: constantes PCB, estados y limites.
- `src/x64/castips.asm`: tabla PCB, PID, registro, estados, contadores, `ps`, `reap`.
- `src/x64/kernel.asm`: inicializacion, includes y comandos.
- `src/x64/user.asm`: getpid (syscall 8), yield (syscall 9), prueba pidtest64.
- `src/x64/scheduler.asm`: sincronizacion de estados con PIT, salida de tareas, yield voluntario.
- `tools/test_castips.py`: pruebas estaticas y ensamblado con NASM cuando esta disponible.
- `tools/test_castips_vm.py`: prueba funcional QEMU para ejecutarse en un sistema con GRUB/QEMU.
- `Makefile`: `make test-castips`, `make castips-asm`, `make test-castips-vm` y tests en `make`.
- `docs/CASTIPS_0_1.md`: interfaz y limitaciones.

## Validacion efectuada en el entorno de desarrollo

- `make test-castips` con NASM 3.02, correcto.
- `make castips-asm` con NASM 3.02, correcto: `build/x64/kernel64.bin` (ensamblado, sin bootloader).
- `make test-hsfs61`, correcto.
- `make` ejecuta las pruebas iniciales y compila la parte i386, pero NO termina: no esta instalado `grub-file` en el entorno de desarrollo.
- NO se ha probado el boot completo en QEMU ni la generacion de ISO en este entorno porque faltan GRUB/QEMU.

**No se incluye `dist/CastiOS-x64-preview.iso` precompilada**: la ISO
antigua correspondia a HSFS6.1, no a CastiPS 0.1. Generala en tu Linux
con `make` (dependencias instaladas) o `make x64`.

## Dependencias Debian/Ubuntu

`sudo apt install make gcc gcc-multilib binutils nasm python3 grub-pc-bin grub-common xorriso qemu-system-x86`

Tras instalar: `make`, o para una ISO solamente x64: `make x64`.
