"""Construye la ISO y un volumen inicial ASFS2; conserva imagenes existentes."""
from pathlib import Path
from fs_format import fresh
root=Path(__file__).resolve().parent.parent
build=root/'build'
boot=(build/'boot.bin').read_bytes()
kernel=(build/'kernel.bin').read_bytes()
assert len(boot)==512 and boot[-2:]==b'\x55\xaa'
assert 0<len(kernel)<=32768
image=bytearray(1474560)
image[:512]=boot
image[512:512+len(kernel)]=kernel
(build/'iso/boot/boot.img').write_bytes(image)
disk=build/'asfs2.img'
if not disk.exists():
    image=bytearray(4*1024*1024)
    fs=fresh();image[:len(fs)]=fs
    with disk.open('xb') as output:output.write(image)
print(f'Kernel {len(kernel)} bytes; ASFS2 conservado: {disk}')
