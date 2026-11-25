"""Four CPL3 processes survive PIT switches, yield and an unknown syscall."""
import re
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
    for slot, name, value in ((210, 'a.app', 11), (211, 'b.app', 22),
                              (212, 'c.app', 33), (213, 'd.app', 44)):
        code = (b'\xb8' + struct.pack('<I', value) +
                b'\xb9' + struct.pack('<I', 12000000) +
                b'\x49\x75\xfd\xc3')
        put(fs, slot, name, b'AX05' + struct.pack('<I', len(code)) + code, kind=3)
    yield_code = b'\xb8\x02\x00\x00\x00\xcd\x80\xb8\x37\x00\x00\x00\xc3'
    bad_code = b'\xb8\x63\x00\x00\x00\xcd\x80\xc3'
    for slot, name, code in ((214, 'yield.app', yield_code),
                             (215, 'bad.app', bad_code)):
        put(fs, slot, name, b'AX05' + struct.pack('<I', len(code)) + code, kind=3)
    seal(fs)
    raw[16*1024*1024:16*1024*1024+SIZE] = fs
    raw[20*1024*1024:20*1024*1024+SIZE] = fs
    disk.write_bytes(raw)
    vm = VM(folder, disk)
    try:
        result = vm.cmd('execall a.app b.app c.app d.app', 'Proceso 4 EAX=44')
        for index, value in enumerate((11, 22, 33, 44), 1):
            assert f'Proceso {index} EAX={value}' in result, result
        switches = re.search(r'cambios de contexto=(\d+)', result)
        assert switches and int(switches.group(1)) > 0, result
        result = vm.cmd('execall yield.app bad.app a.app', 'Proceso 3 EAX=11')
        assert 'Proceso 1 EAX=55' in result, result
        assert 'Proceso 2 EAX=4294967258' in result, result
        vm.cmd('exec a.app', 'EAX=11')
    finally:
        vm.close()
print('Multitarea CPL3: cuatro procesos, PIT, yield, fallo aislado y shell OK.')
