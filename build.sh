#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")"
mkdir -p build
if [[ ! -f build/nasm32 ]]; then
    echo 'Falta NASM i386. Ejecuta bash tools/build_nasm32.sh (gcc multilib, libc estatica i386, autoconf, automake, perl).'
    exit 1
fi
gcc -m32 -Oz -ffreestanding -fno-pie -fno-stack-protector -fno-builtin -mpreferred-stack-boundary=2 -Wall -Wextra -Werror -Wno-unused-function -c src/installer.c -o build/installer.o
ld -m elf_i386 -T src/installer.ld build/installer.o -o build/installer.elf
objcopy -O binary build/installer.elf build/setup.bin
gcc -m32 -Oz -ffreestanding -fno-pie -fno-stack-protector -fno-builtin -mpreferred-stack-boundary=2 -Wall -Wextra -c src/nasm_runtime.c -o build/nasm_runtime.o
ld -m elf_i386 -T src/nasm_runtime.ld build/nasm_runtime.o -o build/nasm_runtime.elf
objcopy -O binary build/nasm_runtime.elf build/nasm_runtime.bin
nasm -w-implicit-abs-deprecated -f bin -Wall -Werror -w-reloc-abs-word src/hddboot.asm -o build/hddboot.bin
video_flags=()
if [[ "${CASTIOS_VIDEO:-}" == text ]]; then video_flags=(-DTEXT_CONSOLE=1); fi
python3 tools/generate_installed_docs.py
nasm "${video_flags[@]}" -w-implicit-abs-deprecated -f bin -Wall -Werror -w-reloc-abs-word -w-reloc-abs-dword src/kernel.asm -o build/kernel.bin
grub-file --is-x86-multiboot build/kernel.bin
python3 tools/grub_build.py
if [[ "${CASTIOS_I386_ONLY:-0}" != 1 ]]; then
    python3 tools/build_x64.py
fi
