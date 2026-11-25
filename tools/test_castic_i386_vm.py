"""Compile real i386 AX05 programs inside CastiOS and execute them in CPL3."""
import os, shutil, tempfile
from pathlib import Path
from vm_harness import ROOT, VM
os.environ.setdefault('VM_WAIT_TIMEOUT', '40')
with tempfile.TemporaryDirectory() as tmp:
    work=Path(tmp); disk=work/'disk.img'
    shutil.copyfile(ROOT/'build/CastiOS-hdd.img', disk)
    vm=VM(work, disk, boot_disk=False, memory=200)
    try:
        vm.cmd('castctl write /math.cas let a 7')
        vm.cmd('castctl append /math.cas add a 5')
        vm.cmd('castctl append /math.cas sub a 3')
        vm.cmd('castctl append /math.cas mul a 4')
        vm.cmd('castctl append /math.cas div a 3')
        vm.cmd('castctl append /math.cas return a')
        vm.cmd('castic /math.cas /math.app', 'compilado i386 AX05')
        vm.cmd('exec /math.app', 'Programa termino. EAX=12')
        vm.cmd('castctl write /zero.cas let z 9;div z 0')
        vm.cmd('castic /zero.cas /zero.app', 'sintaxis invalida')
        vm.cmd('castctl write /undef.cas add b 1')
        vm.cmd('castic /undef.cas /undef.app', 'sintaxis invalida')
        vm.cmd('castctl write /hello.cas print hola mundo')
        vm.cmd('castctl append /hello.cas print segunda linea')
        vm.cmd('castic /hello.cas /hello.app', 'compilado i386 AX05')
        out=vm.cmd('exec /hello.app', 'Programa termino. EAX=0')
        assert 'hola mundo\nsegunda linea\n' in out, out
        vm.cmd('castic /hello.cas /hello.app', 'destino existe')
        vm.cmd('castctl write /bad.cas bad value')
        vm.cmd('castic /bad.cas /bad.app', 'sintaxis invalida')
        vm.cmd('exec /bad.app', 'no existe')
        vm.cmd('castctl write /semi.cas print uno;print dos')
        vm.cmd('castic /semi.cas /semi.app', 'compilado i386 AX05')
        out=vm.cmd('exec /semi.app', 'Programa termino. EAX=0')
        assert 'uno\ndos\n' in out, out
        vm.cmd('castctl write /bad.cas print x')
        vm.cmd('exec /hello.app', 'hola mundo')
    finally: vm.close()
    vm=VM(work, disk, boot_disk=False, memory=200)
    try:
        out=vm.cmd('exec /hello.app', 'Programa termino. EAX=0')
        assert 'hola mundo\nsegunda linea\n' in out, out
    finally: vm.close()
print('Castic i386: compilacion AX05, CPL3, validacion y reinicio OK')
