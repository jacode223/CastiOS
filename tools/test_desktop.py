"""Graphical desktop: taskbar, start menu, real HSFS folder, keyboard navigation."""
import tempfile,time,shutil
from pathlib import Path
from vm_harness import VM,ROOT

def pixel(ppm,x,y):
    parts=ppm.split(b'\n',3)
    assert parts[0]==b'P6',parts[0]
    w,h=map(int,parts[1].split())
    assert w>=1024 and h>=768
    pos=(y*w+x)*3
    return parts[3][pos:pos+3]
with tempfile.TemporaryDirectory() as temp:
    work=Path(temp)
    disk=work/'disk.img';shutil.copyfile(ROOT/'build/asfs4.img',disk)
    vm=VM(work,disk,memory=200)
    try:
        vm.cmd('mkdir /guia')
        vm.cmd('touch /guia/uno')
        vm.type('desktop');vm.key('ret');time.sleep(.2)
        def shot():
            vm.qmp('human-monitor-command',{'command-line':f'screendump {work/"desktop.ppm"}'})
            return (work/'desktop.ppm').read_bytes()
        home=shot()
        assert pixel(home,400,150)==bytes.fromhex('173b59'),pixel(home,400,150)
        assert pixel(home,400,650)==bytes.fromhex('12283d'),pixel(home,400,650)
        vm.key('tab');menu=shot()
        assert pixel(menu,56,382)==bytes.fromhex('2b759f'),pixel(menu,56,382)
        vm.key('esc');vm.key('down');vm.key('ret');time.sleep(.2)
        files=shot()
        assert pixel(files,350,206)==bytes.fromhex('2976a4'),pixel(files,350,206)
        vm.key('down');vm.key('down');vm.key('ret')  # open docs directory
        start=len(vm.out())
        for _ in range(3):vm.key('esc');time.sleep(.08)
        vm.wait('asm:/ > ',start)
        vm.cmd('pwd','/docs/')
        vm.cmd('echo escritorio-ok','escritorio-ok')
    finally:vm.close()
print('Escritorio: barra, Inicio, ventana real de Archivos, teclado y shell OK.')
