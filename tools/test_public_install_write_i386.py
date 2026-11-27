"""Install only to an empty temporary virtual disk and boot it."""
import tempfile
from pathlib import Path
from vm_harness import VM
with tempfile.TemporaryDirectory() as tmp:
    p=Path(tmp); disk=p/'disposable.img'
    with disk.open('wb') as f:f.truncate(64*1024*1024)
    vm=VM(p,disk,memory=200)
    try:
        start=len(vm.out());vm.type('install hda');vm.key('ret')
        vm.wait('Formateado e instalado',start)
        vm.wait('asm:/ > ',start)
    finally:vm.close()
    vm=VM(p,disk,boot_disk=True,memory=200)
    try:
        vm.cmd('disks','hda ')
        vm.cmd('echo instalado-ok','instalado-ok')
    finally:vm.close()
print('install hda: virtual disk installation and disk boot OK')
