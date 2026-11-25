"""CPL3 apps read and persist a bounded root HSFS text file."""
import shutil
import struct
import tempfile
from pathlib import Path

from fs_format import COUNT, RECORD, SIZE, extract_or_migrate, put, seal
from vm_harness import ROOT, VM

def mov(reg, value):
    return bytes([0xb8+reg]) + struct.pack('<I', value)

def call(number):
    return mov(0, number) + b'\xcd\x80'

with tempfile.TemporaryDirectory() as tmp:
    folder = Path(tmp)
    disk = folder/'disk.img'
    shutil.copyfile(ROOT/'build/CastiOS-hdd.img', disk)
    with disk.open('r+b') as f:
        f.seek(16*1024*1024)
        fs = extract_or_migrate(f.read(SIZE))
        free = (i for i in range(COUNT) if not fs[512+i*RECORD])
        put(fs, next(free), 'demo', b'Hola', kind=1)
        code = (mov(0, 0x6f6d6564) + mov(3, 0x20000001) + mov(1, 4) +
                call(6) + mov(3, 3) + mov(1, 0x20002000) + mov(2, 4) +
                call(7) + mov(3, 0x20002000) + mov(1, 4) + call(5) + b'\xc3')
        put(fs, next(free), 'files.app', b'AX05'+struct.pack('<I',len(code))+code, kind=3)
        write = (mov(0, 0x6f6d6564) + mov(3, 0x20000001) + mov(1, 4) +
                 call(6) + mov(0, 0x21657942) + mov(3, 3) +
                 mov(1, 0x20000000+23) + mov(2, 4) + call(10) + b'\xc3')
        save_slot=next(free)
        put(fs, save_slot, 'save.app', b'AX05'+struct.pack('<I',len(write))+write, kind=3)
        struct.pack_into('<I',fs,512+save_slot*RECORD+56,1)
        put(fs, next(free), 'denied.app', b'AX05'+struct.pack('<I',len(write))+write, kind=3)
        readcode=(mov(0, 0x6f6d6564) + mov(3, 0x20000001) + mov(1, 4) +
                  call(6) + mov(3, 3) + mov(1, 0x20000000) + mov(2, 4) +
                  call(7) + b'\xc3')
        put(fs, next(free), 'readcode.app', b'AX05'+struct.pack('<I',len(readcode))+readcode, kind=3)
        bad = mov(3, 0x1000) + mov(1, 4) + call(6) + b'\xc3'
        put(fs, next(free), 'badfile.app', b'AX05'+struct.pack('<I',len(bad))+bad, kind=3)
        stat = (mov(0, 0x6f6d6564) + mov(3, 0x20000001) + mov(1, 4) +
                mov(2, 0x20002000) +
                call(9) + b'\xc3')
        put(fs, next(free), 'stat.app', b'AX05'+struct.pack('<I',len(stat))+stat, kind=3)
        close = (mov(0, 0x6f6d6564) + mov(3, 0x20000001) + mov(1, 4) +
                 call(6) + mov(3, 3) + call(8) + b'\xc3')
        put(fs, next(free), 'close.app', b'AX05'+struct.pack('<I',len(close))+close, kind=3)
        seal(fs)
        for off in (16*1024*1024, 20*1024*1024):
            f.seek(off)
            f.write(fs)
    vm = VM(folder, disk, boot_disk=True)
    try:
        result = vm.cmd('exec files.app', 'EAX=4')
        assert 'Hola' in result, result
        vm.cmd('exec badfile.app', 'EAX=4294967282')
        vm.cmd('exec readcode.app', 'EAX=4294967282')
        vm.cmd('exec stat.app', 'EAX=0')
        vm.cmd('exec close.app', 'EAX=0')
        vm.cmd('exec denied.app', 'EAX=4294967283')  # -EACCES
        vm.cmd('chmod denied.app', 'escritura denegada')
        vm.cmd('cat demo', 'Hola')
        vm.cmd('chmod denied.app +w', 'Guardado en disco')
        vm.cmd('chmod denied.app', 'lectura y escritura')
        vm.cmd('exec denied.app', 'EAX=4')
        vm.cmd('chmod denied.app -w', 'Guardado en disco')
        vm.cmd('exec denied.app', 'EAX=4294967283')
        vm.cmd('exec save.app', 'EAX=4')
        vm.cmd('cat demo', 'Bye!')
        vm.cmd('echo shell-viva', 'shell-viva')
    finally:
        vm.close()
    vm = VM(folder, disk, boot_disk=True)
    try:
        vm.cmd('cat demo', 'Bye!')
        vm.cmd('exec denied.app', 'EAX=4294967283')
    finally:
        vm.close()
print('AX05 archivos: open/read/write, persistencia y fallo de puntero OK.')
