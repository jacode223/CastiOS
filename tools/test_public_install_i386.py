"""Public disk commands: inventory and cancelled install never modify the disk."""
import hashlib, tempfile
from pathlib import Path
from vm_harness import VM
with tempfile.TemporaryDirectory() as tmp:
    p=Path(tmp); disk=p/'test.img'
    with disk.open('wb') as f: f.truncate(48*1024*1024)
    before=hashlib.sha256(disk.read_bytes()).digest()
    vm=VM(p,disk,memory=200)
    try:
        out=vm.cmd('disks','hda ')
        assert 'sectores' in out and 'hdb ' in out,out
        vm.cmd('install bad','Uso: install hda|hdb|hdc|hdd')
        start=len(vm.out());vm.type('install');vm.key('ret')
        vm.wait('SETUP WELCOME',start);vm.key('esc')
        vm.wait('Instalacion cancelada. Discos sin cambios.',start)
        vm.wait('asm:/ > ',start)
        vm.cmd('echo sistema-vivo','sistema-vivo')
    finally: vm.close()
    assert hashlib.sha256(disk.read_bytes()).digest()==before,'cancelled installation changed disk'
print('disks/install: direct commands, confirmation and safe cancellation OK')
