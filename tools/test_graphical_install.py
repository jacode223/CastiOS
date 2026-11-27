"""Live wizard: cancellation, target selection, verified install and disk boot.
Only temporary QEMU image files are written. Never uses host block devices.
"""
import hashlib
import tempfile
from pathlib import Path
from vm_harness import VM, ROOT

def digest(p):
    with p.open('rb') as f:
        return hashlib.file_digest(f,'sha256').hexdigest()

def start(vm):
    off=len(vm.out());vm.type('install');vm.key('ret')
    vm.wait('SETUP WELCOME',off)
    return off

with tempfile.TemporaryDirectory() as tmp:
    p=Path(tmp);first=p/'keep.img';second=p/'target.img'
    for path in (first,second):
        with path.open('wb') as f:f.truncate(48*1024*1024)
    with first.open('r+b') as f:
        f.seek(1024*1024);f.write(b'KEEP THIS DISK')
    before=[digest(first),digest(second)]
    vm=VM(p,first,slave=second,memory=256)
    try:
        off=start(vm)
        vm.qmp('screendump',{'filename':str(ROOT/'build/setup-welcome.ppm')})
        vm.key('esc');vm.wait('Instalacion cancelada',off);vm.wait('asm:/ > ',off)
        off=start(vm);vm.key('ret');vm.wait('SETUP DISKS',off)
        vm.key('2');vm.key('ret');vm.wait('SETUP CONFIRM',off)
        vm.type('FORMAT hda');vm.key('ret');vm.wait('SETUP MISMATCH',off)
        vm.qmp('screendump',{'filename':str(ROOT/'build/setup-confirm.ppm')})
        vm.key('esc');vm.key('esc');vm.wait('asm:/ > ',off)
        assert [digest(first),digest(second)]==before,'cancel/mismatch changed disks'
        off=start(vm);vm.key('ret');vm.wait('SETUP DISKS',off)
        vm.key('2');vm.key('ret');vm.wait('SETUP CONFIRM',off)
        vm.type('FORMAT hdb');vm.key('ret')
        vm.wait('Verificando lectura del disco...',off)
        vm.wait('Formateado e instalado.',off)
        vm.qmp('screendump',{'filename':str(ROOT/'build/setup-complete.ppm')})
        vm.key('ret');vm.wait('asm:/ > ',off)
        vm.cmd('ls /','docs')
    finally:vm.close()
    assert digest(first)==before[0],'non-selected disk changed'
    assert digest(second)!=before[1],'target was not installed'
    # Boot with both drives present: hdb configuration must remain hdb.
    boot=p/'boot';boot.mkdir()
    vm=VM(boot,first,slave=second,boot_disk=True,boot_slave=True,memory=256)
    try:
        vm.cmd('uname','0.37-exp1')
        vm.cmd('ls /','docs')
        vm.cmd('install','Arranca la ISO Live')
        vm.cmd('castctl write saved.txt persisted','')
        vm.cmd('cat saved.txt','persisted')
    finally:vm.close()
    again=p/'again';again.mkdir()
    vm=VM(again,first,slave=second,boot_disk=True,boot_slave=True,memory=256)
    try:vm.cmd('cat saved.txt','persisted')
    finally:vm.close()
    assert digest(first)==before[0],'boot modified other disk'
print('OK: graphical cancel, mismatch, selected hdb, readback, HDD boot and persistence')
