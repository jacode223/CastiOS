"""ABI AX05: register results, bounded user write, and process isolation."""
import re
import shutil
import struct
import tempfile
from pathlib import Path

from fs_format import SIZE, extract_or_migrate, put, seal
from vm_harness import ROOT, VM


def imm(reg, value):
    return bytes([0xB8 + reg]) + struct.pack('<I', value)


def app(code):
    return b'AX05' + struct.pack('<I', len(code)) + code


with tempfile.TemporaryDirectory() as tmp:
    work = Path(tmp)
    disk = work / 'disk.img'
    shutil.copyfile(ROOT / 'build/CastiOS-hdd.img', disk)
    raw = bytearray(disk.read_bytes())
    fs = extract_or_migrate(raw)
    write = (imm(0, 0x616c6f48) + imm(3, 0x20000001) +
             imm(1, 4) + imm(0, 5) + b'\xcd\x80\xc3')
    cases = {
        'pid.app': imm(0, 3) + b'\xcd\x80\xc3',
        'tick.app': imm(0, 4) + b'\xcd\x80\xc3',
        'write.app': write,
        'fault.app': imm(3, 0x1000) + imm(1, 4) + imm(0, 5) + b'\xcd\x80\xc3',
        'limit.app': imm(3, 0x20000001) + imm(1, 257) + imm(0, 5) + b'\xcd\x80\xc3',
        'unknown.app': imm(0, 99) + b'\xcd\x80\xc3',
    }
    for slot, (name, code) in enumerate(cases.items(), 220):
        put(fs, slot, name, app(code), kind=3)
    seal(fs)
    raw[16 * 1024 * 1024:16 * 1024 * 1024 + SIZE] = fs
    raw[20 * 1024 * 1024:20 * 1024 * 1024 + SIZE] = fs
    disk.write_bytes(raw)
    vm = VM(work, disk)
    try:
        vm.cmd('exec pid.app', 'EAX=1')
        result = vm.cmd('exec tick.app')
        assert re.search(r'EAX=\d+', result), result
        result = vm.cmd('exec write.app', 'EAX=4')
        assert 'Hola' in result, result
        vm.cmd('exec fault.app', 'EAX=4294967282')  # -EFAULT
        vm.cmd('exec limit.app', 'EAX=4294967274')  # -EINVAL
        vm.cmd('exec unknown.app', 'EAX=4294967258')  # -ENOSYS
        result = vm.cmd('execall pid.app write.app', 'Proceso 2 EAX=4')
        assert 'Proceso 1 EAX=1' in result and 'Hola' in result, result
        vm.cmd('castctl write mine.asm bits 32')
        for line in ('mov eax, 3', 'int 0x80', 'ret'):
            vm.cmd('castctl append mine.asm ' + line)
        vm.cmd('castctl asm mine.asm mine.app', 'Ensamblado AX05 listo.')
        vm.cmd('exec mine.app', 'EAX=1')
        vm.cmd('echo sigue', 'sigue')
    finally:
        vm.close()
print('Syscalls AX05: PID, ticks, escritura acotada, errores y multitarea OK.')
