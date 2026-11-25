"""The shell remains usable while CPL3 processes run in the background."""
import shutil
import struct
import tempfile
from pathlib import Path
from fs_format import SIZE, extract_or_migrate, put, seal
from vm_harness import VM, ROOT

with tempfile.TemporaryDirectory() as tmp:
    folder = Path(tmp)
    disk = folder / 'disk.img'
    shutil.copyfile(ROOT / 'build/CastiOS-hdd.img', disk)
    raw = bytearray(disk.read_bytes())
    fs = extract_or_migrate(raw)
    for slot, name, value in ((210, 'a.app', 11), (211, 'b.app', 22)):
        code = (b'\xb8' + struct.pack('<I', value) +
                b'\xb9' + struct.pack('<I', 30000000) +
                b'\x49\x75\xfd\xc3')
        put(fs, slot, name, b'AX05' + struct.pack('<I', len(code)) + code, kind=3)
    bad = b'\xb8\x63\x00\x00\x00\xcd\x80\xc3'
    put(fs, 212, 'bad.app', b'AX05' + struct.pack('<I', len(bad)) + bad, kind=3)
    seal(fs)
    raw[16*1024*1024:16*1024*1024+SIZE] = fs
    raw[20*1024*1024:20*1024*1024+SIZE] = fs
    disk.write_bytes(raw)
    vm = VM(folder, disk)
    try:
        vm.cmd('bg a.app', 'Proceso de fondo iniciado: 1')
        vm.cmd('bg b.app', 'Proceso de fondo iniciado: 2')
        vm.cmd('bg bad.app', 'Proceso de fondo iniciado: 3')
        vm.cmd('echo shell-viva', 'shell-viva')
        vm.cmd('ps', 'Proceso 1')
        result = vm.cmd('wait', 'Proceso 3 terminado EAX=4294967258')
        assert 'Proceso 1 terminado EAX=11' in result
        assert 'Proceso 2 terminado EAX=22' in result
        vm.cmd('ps', 'Sin procesos de fondo')
        vm.cmd('execall a.app b.app', 'Proceso 2 EAX=22')
    finally:
        vm.close()
print('Fondo CPL3: shell activa, tres tareas, error aislado y memoria liberada.')
