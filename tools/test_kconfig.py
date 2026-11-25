"""Kernel settings are editable inside CastiOS and survive a fresh boot."""
import shutil
import tempfile
from pathlib import Path
from vm_harness import VM, ROOT

with tempfile.TemporaryDirectory() as tmp:
    folder = Path(tmp)
    disk = folder / 'disk.img'
    shutil.copyfile(ROOT / 'build/CastiOS-hdd.img', disk)
    vm = VM(folder, disk)
    try:
        vm.cmd('castctl kset color green', 'Guardado en disco')
        vm.cmd('castctl kshow', 'color=green')
        start = len(vm.out())
        vm.type('castctl kset prompt MYOS')
        vm.key('ret')
        vm.wait('Guardado en disco ASFS.\nMYOS', start)
    finally:
        vm.close()
    vm = VM(folder, disk, prompt='MYOS')
    try:
        result = vm.cmd('castctl kshow', 'color=green')
        assert 'prompt=MYOS' in result
        vm.cmd('castctl write system.cfg invalido', 'Guardado en disco')
        vm.cmd('castctl kreload', 'system.cfg invalido')
        vm.cmd('castctl kshow', 'prompt=MYOS')
    finally:
        vm.close()
print('Configuracion del sistema: aplicada, persistente y validada OK.')
