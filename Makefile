# make: compila CastiOS i386 y la ISO x86-64 con HSFS6.1.
# Necesita gcc multilib, nasm, binutils, grub-file, grub-mkimage, xorriso.
.PHONY: all run run-x64-hsfs61 test test-hsfs61 test-hsfs61-vm test-castips test-castips-vm castips-asm x64 image-hsfs61 package

all:
	python3 tools/test_castips.py
	python3 tools/test_hsfs61_unit.py
	bash build.sh

x64:
	python3 tools/build_x64.py

image-hsfs61:
	@mkdir -p build
	@test -e build/hsfs61-demo.img || python3 tools/hsfs6.py mkfs build/hsfs61-demo.img --size-mib 128

run:
	bash run.sh

run-x64-hsfs61: x64 image-hsfs61
	qemu-system-x86_64 -m 256 -boot d -cdrom dist/CastiOS-x64-preview.iso -drive file=build/hsfs61-demo.img,format=raw,if=ide,index=0

test-hsfs61:
	python3 tools/test_hsfs61_unit.py

test-hsfs61-vm: x64
	python3 tools/test_hsfs61_vm.py

test: all
	python3 tools/test_i386_candidate.py

package: all
	python3 tools/package.py

# CastiPS 0.1: static source validation and optional emulator integration.
test-castips:
	python3 tools/test_castips.py

test-castips-vm: x64
	python3 tools/test_castips_vm.py

# Compilar solamente el kernel x64 sin herramientas de generacion de ISO.
castips-asm:
	@mkdir -p build/x64
	nasm -f bin examples/shell64/shell.asm -o build/x64/sample_shell.bin
	nasm -f bin -Wall -Werror -w-implicit-abs-deprecated -w-reloc-abs-word -w-reloc-abs-dword -w-reloc-abs-qword src/x64/kernel.asm -o build/x64/kernel64.bin

.PHONY: test-fat32-large test-usb-hid test-usb-large-vm
test-fat32-large:
	@mkdir -p build
	gcc -O2 -Wall -Wextra -Wno-unused-function tools/test_fat32_large_host.c -o build/test_fat32_large
	./build/test_fat32_large

test-usb-hid:
	@mkdir -p build
	gcc -Wall -Wextra tools/test_usb_hid_host.c -o build/test_usb_hid_host
	./build/test_usb_hid_host

test-usb-large-vm:
	python3 tools/test_usb_large_vm.py

.PHONY: i386
i386:
	CASTIOS_I386_ONLY=1 bash build.sh
