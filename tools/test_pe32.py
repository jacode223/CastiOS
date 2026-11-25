"""Validate bounded PE32 parsing and its QEMU command without executing PE code."""
import shutil
import struct
import tempfile
from pathlib import Path
from fs_format import SIZE, extract_or_migrate, put, seal
from vm_harness import ROOT, VM


def sample():
    b = bytearray(1024)
    def word(pos, value): struct.pack_into('<H', b, pos, value)
    def dword(pos, value): struct.pack_into('<I', b, pos, value)
    word(0, 0x5a4d); dword(0x3c, 0x80)
    b[0x80:0x84] = b'PE\0\0'
    word(0x84, 0x14c); word(0x86, 1); word(0x94, 0xe0)
    opt = 0x98
    word(opt, 0x10b); dword(opt+16, 0x1000); dword(opt+28, 0x400000)
    dword(opt+56, 0x2000); word(opt+68, 3); dword(opt+92, 16)
    dword(opt+104, 0x1100); dword(opt+108, 40)
    section = 0x178
    b[section:section+5] = b'.text'
    dword(section+8, 512); dword(section+12, 0x1000)
    dword(section+16, 512); dword(section+20, 0x200)
    dword(0x300, 0x1140); dword(0x30c, 0x1180); dword(0x310, 0x1160)
    dword(0x340, 0x11a0); dword(0x344, 0)
    b[0x380:0x38d] = b'KERNEL32.dll\0'
    b[0x3a2:0x3ae] = b'ExitProcess\0'
    return b


with tempfile.TemporaryDirectory() as tmp:
    p = Path(tmp); disk = p/'disk.img'
    shutil.copyfile(ROOT/'build/CastiOS-hdd.img', disk)
    with disk.open('r+b') as f:
        f.seek(16*1024*1024)
        fs = extract_or_migrate(f.read(SIZE))
        good = sample()
        bad = bytearray(good); struct.pack_into('<I', bad, 0x340, 0x7fffffff)
        amd64 = bytearray(good); struct.pack_into('<H', amd64, 0x84, 0x8664)
        resources = bytearray(good)
        struct.pack_into('<II', resources, 0x98+112, 0x1020, 24)
        struct.pack_into('<H', resources, 0x220+14, 1)
        brokenres = bytearray(resources)
        struct.pack_into('<H', brokenres, 0x220+14, 2)
        put(fs, 233, 'rsrc.exe', resources, kind=3)
        put(fs, 234, 'rsbad.exe', brokenres, kind=3)
        put(fs, 230, 'valid.exe', good, kind=3)
        put(fs, 231, 'bad.exe', bad, kind=3)
        put(fs, 232, 'amd64.exe', amd64, kind=3)
        seal(fs)
        for off in (16*1024*1024, 20*1024*1024):
            f.seek(off); f.write(fs)
    vm = VM(p,disk,memory=200)
    try:
        result = vm.cmd('castctl peinfo valid.exe', 'DLL importadas 1')
        assert 'KERNEL32.dll! ExitProcess' in result, result
        assert 'Inspeccion solamente' in result, result
        vm.cmd('castctl peinfo rsrc.exe', 'Recursos: 1 tipos')
        vm.cmd('castctl peinfo rsbad.exe', 'directorio de recursos invalido')
        vm.cmd('castctl peinfo bad.exe', 'directorio de importaciones invalido')
        vm.cmd('castctl peinfo amd64.exe', 'solo PE32 x86')
        vm.cmd('castctl peinfo none.exe', 'no encontrado')
        vm.cmd('echo pe-sigue', 'pe-sigue')
    finally: vm.close()
print('PE32: importaciones, RVA malformado, arquitectura y kernel vivo OK.')
