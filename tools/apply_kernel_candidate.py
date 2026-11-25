"""Stage an in-CastiOS NASM kernel build onto a new disk and boot-test it.

Power off CastiOS before running. The original disk is never modified; keep it
as the recovery image. A failing candidate is discarded without publishing.
"""
import argparse
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile

from fs_format import COUNT, RECORD, ROOT, SIZE, body, extract_or_migrate
from vm_harness import VM

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('old_disk', type=Path)
p.add_argument('new_disk', type=Path)
p.add_argument('--candidate', default='kernel.new', help='HSFS file in the root')
args = p.parse_args()
source = args.old_disk.resolve()
destination = args.new_disk.resolve()
if (not source.is_file() or destination.exists() or source == destination or
        not args.candidate.isascii() or '/' in args.candidate or len(args.candidate) > 31):
    p.error('Origen/destino/candidato incorrecto; el destino debe ser nuevo')

with source.open('rb') as f:
    if f.seek(0, 2) < 32 * 1024 * 1024:
        p.error('Imagen demasiado pequena')
    f.seek(16 * 1024 * 1024)
    fs = extract_or_migrate(f.read(SIZE))
for i in range(COUNT):
    record = fs[512+i*RECORD:512+(i+1)*RECORD]
    if (record[0] and struct.unpack_from('<I', record, 32)[0] == ROOT and
            record[:32].split(b'\0', 1)[0] == args.candidate.encode()):
        if struct.unpack_from('<I', record, 36)[0] not in (1, 3):
            p.error('El candidato no es un archivo normal')
        candidate = body(fs, i)
        break
else:
    p.error('Candidato no encontrado en la raiz HSFS')

if not 64 <= len(candidate) <= 0x20000:
    p.error('Kernel demasiado pequeno o supera el area segura 0x10000..0x30000')
magic, flags, check, header, load, end, bss, entry = struct.unpack_from('<8I', candidate)
if (magic != 0x1badb002 or (magic+flags+check) & 0xffffffff or
        flags not in (0x10003, 0x10007) or header != load or load != 0x10000 or
        end != load+len(candidate) or bss < end or bss > 0x30000 or
        not load <= entry < end):
    p.error('Cabecera Multiboot o rango de carga incompatible')

try:
    with tempfile.TemporaryDirectory(dir=destination.parent) as temp:
        work = Path(temp)
        binary = work / 'kernel.bin'
        binary.write_bytes(candidate)
        subprocess.run(['grub-file', '--is-x86-multiboot', str(binary)], check=True)
        staged = work / 'candidate.img'
        shutil.copyfile(source, staged)
        with staged.open('r+b') as f:
            f.seek(696 * 512)
            slot = f.read(512)
            f.seek(708 * 512)
            stable = f.read(4)
            if slot.startswith(b'set default=') and slot[16:31] == b'CASTIOS-SLOT-V1' and stable == b'\x02\xb0\xad\x1b':
                # A/B image: patch only the fixed stable extent on the new copy.
                f.seek(708 * 512)
                f.write(candidate.ljust(131072, b'\0'))
                f.seek(696 * 512)
                f.write(slot[:12] + b'0' + slot[13:])
            else:
                # Legacy image without A/B slots: regenerate its GRUB ISO.
                installer = work / 'installer.iso'
                base = Path(__file__).resolve().parent.parent / 'build/installer.iso'
                subprocess.run(['xorriso', '-indev', str(base), '-outdev', str(installer),
                                '-map', str(binary), '/boot/kernel.bin',
                                '-boot_image', 'any', 'replay', '-commit', '-end'],
                               check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                boot = installer.read_bytes()
                if len(boot) >= 16 * 1024 * 1024:
                    p.error('ISO de arranque excede la reserva de 16 MiB')
                f.seek(0)
                f.write(boot)
                f.write(bytes(16 * 1024 * 1024 - len(boot)))
            f.flush()
            os.fsync(f.fileno())
        vm = VM(work, staged, boot_disk=True)
        try:
            vm.cmd('uname', 'CastiOS')
            vm.cmd('echo kernel-ok', 'kernel-ok')
            vm.cmd('cat /docs/KERNEL.TXT', 'FUENTES Y KERNEL')
        finally:
            vm.close()
        if destination.exists():
            p.error('Destino creado concurrentemente; no se sobrescribe')
        staged.replace(destination)
except (OSError, ValueError, AssertionError, subprocess.CalledProcessError) as error:
    raise SystemExit(f'Candidato rechazado; el disco original sigue intacto: {error}')
print(f'Kernel verificado en QEMU. Disco nuevo: {destination}. Conserva {source} como rescate.')
