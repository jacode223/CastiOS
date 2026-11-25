"""A/B internal update from HSFS small and large .img, invalid image, rollback."""
import shutil
import struct
import tempfile
from pathlib import Path

from fs_format import COUNT, RECORD, ROOT as FSROOT, SIZE, extract_or_migrate, put, seal
from vm_harness import ROOT, VM

with tempfile.TemporaryDirectory() as temp:
    work = Path(temp)
    disk = work/'disk.img'
    shutil.copyfile(ROOT/'build/CastiOS-hdd.img', disk)
    kernel = (ROOT/'build/kernel.bin').read_bytes().replace(b'CastiOS 0.36', b'CastiOS 0.99')
    assert b'CastiOS 0.99' in kernel
    with disk.open('r+b') as f:
        f.seek(16*1024*1024)
        fs = extract_or_migrate(f.read(SIZE))
        free = (i for i in range(COUNT) if not fs[512+i*RECORD])
        put(fs, next(free), 'wrong.img', b'invalid kernel', kind=3)
        put(fs, next(free), 'kernel.img', kernel, kind=3)
        # The large-file record points to sectors outside the HSFS mirrors.
        index = next(free)
        record = 512+index*RECORD
        fs[record:record+10] = b'large.img\0'
        struct.pack_into('<III', fs, record+32, FSROOT, 5, len(kernel))
        struct.pack_into('<II', fs, record+48, 20000, (len(kernel)+511)//512)
        seal(fs)
        for offset in (16*1024*1024, 20*1024*1024):
            f.seek(offset)
            f.write(fs)
        f.seek((32768+20000)*512)
        f.write(kernel.ljust((len(kernel)+511)//512*512, b'\0'))
    vm = VM(work, disk, boot_disk=True)
    try:
        vm.cmd('castctl kstatus', 'Arranque seleccionado: estable')
        vm.cmd('castctl kapply wrong.img', 'Kernel IMG incompatible')
        vm.cmd('castctl kstatus', 'Arranque seleccionado: estable')
        vm.cmd('castctl kapply large.img', 'Kernel nuevo verificado y seleccionado')
        vm.cmd('castctl kstatus', 'Arranque seleccionado: kernel nuevo')
    finally:
        vm.close()
    vm = VM(work, disk, boot_disk=True)
    try:
        vm.cmd('uname', 'CastiOS 0.99')
        vm.cmd('castctl kstatus', 'Arranque seleccionado: estable')
    finally:
        vm.close()
    vm = VM(work, disk, boot_disk=True)
    try:
        vm.cmd('uname', 'CastiOS 0.36')
        vm.cmd('castctl kaccept', 'Confirma solo desde la sesion')
        vm.cmd('castctl kapply kernel.img', 'Kernel nuevo verificado y seleccionado')
    finally:
        vm.close()
    vm = VM(work, disk, boot_disk=True)
    try:
        vm.cmd('uname', 'CastiOS 0.99')
        vm.cmd('castctl kaccept', 'Kernel nuevo confirmado')
        vm.cmd('castctl kstatus', 'Arranque seleccionado: kernel nuevo')
    finally:
        vm.close()
    vm = VM(work, disk, boot_disk=True)
    try:
        vm.cmd('uname', 'CastiOS 0.99')
        vm.cmd('castctl krollback', 'Arranque estable seleccionado')
    finally:
        vm.close()
    vm = VM(work, disk, boot_disk=True)
    try:
        vm.cmd('uname', 'CastiOS 0.36')
    finally:
        vm.close()
print('Actualizacion A/B: intento unico, confirmacion, rollback y rechazo OK.')
