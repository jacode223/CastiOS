"""Public command table rejects legacy names; local cp/mv retain data."""
import os
import shutil
import tempfile
from pathlib import Path
from vm_harness import VM, ROOT

os.environ['QEMU_EXTRA_ARGS'] = os.environ.get('QEMU_EXTRA_ARGS', '') + ' -m 256'
with tempfile.TemporaryDirectory() as tmp:
    folder = Path(tmp)
    disk = folder / 'disk.img'
    shutil.copyfile(ROOT / 'build/CastiOS-hdd.img', disk)
    vm = VM(folder, disk)
    try:
        help_text = vm.cmd('help')
        assert 'mv ORIGEN DESTINO' in help_text
        assert 'castctl SUBCOMANDO' in help_text
        assert '\ndir - ' not in help_text
        vm.cmd('uname', 'CastiOS 0.20')
        for old in ('dir', 'type', 'version', 'write', 'speed', 'usbscan', 'waitbg', 'run2'):
            vm.cmd(old, 'Comando desconocido')
        vm.cmd('castctl write demo.txt Hola', 'Guardado en disco')
        vm.cmd('cp demo.txt copia.txt', 'Copiado:')
        vm.cmd('cat copia.txt', 'Hola')
        vm.cmd('mv copia.txt nuevo.txt', 'Guardado en disco')
        vm.cmd('cat nuevo.txt', 'Hola')
        vm.cmd('cat copia.txt', 'El archivo no existe')
        vm.cmd('castctl raminfo', 'RMFS /ram')
    finally:
        vm.close()
print('Shell Unix: nombres publicos, bloqueo de legacy, cp y mv locales OK.')
