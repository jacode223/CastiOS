"""End-to-end in-guest NASM rebuild and host-side immutable boot preflight."""
import shutil
import subprocess
import tempfile
import struct
from pathlib import Path

from fs_format import COUNT, RECORD, ROOT as FSROOT, SIZE, extract_or_migrate, put, seal
from vm_harness import ROOT, VM

with tempfile.TemporaryDirectory() as tmp:
    folder = Path(tmp)
    old, new = folder/'old.img', folder/'new.img'
    shutil.copyfile(ROOT/'build/CastiOS-hdd.img', old)
    vm = VM(folder, old, boot_disk=True)
    try:
        vm.cmd('castctl kbuild', 'NASM terminado: OK')
    finally:
        vm.close()
    subprocess.run(['python3', str(ROOT/'tools/apply_kernel_candidate.py'),
                    str(old), str(new), '--candidate', 'kernel.img'], check=True)
    assert old.exists() and new.exists()

    # Header corruption is rejected without publishing another disk.
    with old.open('r+b') as disk:
        disk.seek(16*1024*1024)
        fs = extract_or_migrate(disk.read(SIZE))
        broken = bytearray((ROOT/'build/kernel.bin').read_bytes())
        broken[0] = 0
        index = next(i for i in range(COUNT)
                     if fs[512+i*RECORD:512+i*RECORD+11] == b'kernel.img\0'
                     and struct.unpack_from('<I', fs, 512+i*RECORD+32)[0] == FSROOT)
        put(fs, index, 'kernel.img', broken, kind=3)
        seal(fs)
        for offset in (16*1024*1024, 20*1024*1024):
            disk.seek(offset)
            disk.write(fs)
    rejected = folder/'rejected.img'
    result = subprocess.run(['python3', str(ROOT/'tools/apply_kernel_candidate.py'),
                             str(old), str(rejected), '--candidate', 'kernel.img'], capture_output=True)
    assert result.returncode and not rejected.exists()

    # Syntax failure never changes the bootable old disk.
    vm = VM(folder, old, boot_disk=True)
    try:
        vm.cmd('castctl append src/process.asm mov xyz, xyz')
        vm.cmd('castctl kbuild', 'NASM error; transaccion descartada')
    finally:
        vm.close()
    vm = VM(folder, old, boot_disk=True)
    try:
        vm.cmd('uname', 'CastiOS 0.36')
    finally:
        vm.close()
print('Kernel: recompilacion interna, preflight, rechazo y recuperacion OK.')
