"""Deleted large HSFS files leave reusable disk extents."""
import os
import shutil
import struct
import subprocess
import tempfile
from pathlib import Path

from fs_format import COUNT, RECORD, ROOT as FSROOT, SIZE, extract_or_migrate
from test_external import fat_image
from vm_harness import ROOT, VM

os.environ.setdefault('VM_WAIT_TIMEOUT','45')
with tempfile.TemporaryDirectory() as temp:
    work = Path(temp)
    disk = work/'disk.img'
    shutil.copyfile(ROOT/'build/CastiOS-hdd.img',disk)
    fat,_ = fat_image(work,partition=False)
    for name,byte in (('A.BIN',b'A'),('B.BIN',b'B'),('C.BIN',b'C')):
        source = work/name
        source.write_bytes(byte*1100000)
        subprocess.run(['mcopy','-i',str(fat),str(source),'::/'+name],check=True,capture_output=True)
    vm=VM(work,disk,boot_disk=True,slave=fat,memory=200)
    try:
        vm.cmd('castctl mount hdb /mnt/data','Montado FAT32')
        vm.cmd('cp /mnt/data/A.BIN /a.bin','Copiado a HSFS')
        vm.cmd('cp /mnt/data/B.BIN /b.bin','Copiado a HSFS')
        vm.cmd('rm /a.bin')
        vm.cmd('cp /mnt/data/C.BIN /c.bin','Copiado a HSFS')
    finally:
        vm.close()
    with disk.open('rb') as stream:
        stream.seek(16*1024*1024)
        fs=extract_or_migrate(stream.read(SIZE))
    def sector(name):
        for i in range(COUNT):
            off=512+i*RECORD
            if fs[off] and struct.unpack_from('<I',fs,off+32)[0]==FSROOT and bytes(fs[off:off+32]).split(b'\0',1)[0]==name:
                assert struct.unpack_from('<I',fs,off+36)[0]==5
                return struct.unpack_from('<I',fs,off+48)[0]
        raise AssertionError(name)
    assert sector(b'c.bin')==16384
    assert sector(b'b.bin')>sector(b'c.bin')
print('HSFS grande: reutiliza el hueco tras borrar, sin solapar otros archivos.')
