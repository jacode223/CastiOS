"""Compile ABI boundary cases and inspect the edge before the app exits."""
import tempfile
from pathlib import Path

from PIL import Image
from fs_format import fresh, put, seal
from vm_harness import VM

cases = {
    'fit': ("syscall(23,'ABCD',49284064,16777215,a);", 0),  # (992,752)
    'empty': ("syscall(23,0,0,0,a);", -22),
    'ctrl': ("syscall(23,10,0,0,a);", -22),
    'bottom': ("syscall(23,'x',49348608,0,a);", -22),  # (0,753)
    'slot': ("syscall(24,4,0,0,a);", -22),
    'cap': ("syscall(24,0,0,0,a);", 65536),
}
with tempfile.TemporaryDirectory() as temporary:
    work = Path(temporary)
    fs = fresh()
    for index, (name, (call, result)) in enumerate(cases.items(), 60):
        put(fs, index, name+'.cas', (call+' return a;').encode())
    put(fs, 70, 'edge.cas',
        b"syscall(21,1000,1048600,66051,b); syscall(23,'ABCD',1000,16777215,a); syscall(22,0,0,0,b); return a;")
    put(fs, 71, 'long.cas', b"syscall(23,'ABCDE',0,0,a); return a;")
    disk = work / 'data.img'
    seal(fs)
    with disk.open('wb') as output:
        output.truncate(32*1024*1024)
        output.seek(0); output.write(fs)
        output.seek(8192*512); output.write(fs)
    vm = VM(work, disk)
    try:
        for name, (_, result) in cases.items():
            vm.cmd(f'castic {name}.cas {name}.app', 'compilado i386')
            vm.cmd(f'exec {name}.app', f'EAX={result & 0xffffffff}')
        vm.cmd('castic long.cas long.app', 'sintaxis invalida')
        vm.cmd('castic edge.cas edge.app', 'compilado i386')
        start = len(vm.out())
        vm.type('exec edge.app'); vm.key('ret')
        vm.wait('exec edge.app\n', start)
        import time
        deadline = time.monotonic()+5
        while time.monotonic() < deadline:
            path = work / 'screen.ppm'
            vm.qmp('screendump', {'filename': str(path)})
            with Image.open(path) as frame:
                colors = frame.crop((1000,0,1024,16)).getcolors()
            if colors == [(384, (1, 2, 3))]:
                break
        else:
            raise AssertionError('Right edge was not left intact')
        vm.key('q')
        vm.wait('EAX=4294967274', start)
    finally:
        vm.close()
print('OK: packed text, viewport boundaries, atomic rejection and disk capacity ABI.')
