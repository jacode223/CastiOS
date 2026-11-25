"""PS/2 mouse packets, buttons, keyboard and desktop in QEMU."""
import tempfile,time,shutil
from pathlib import Path
from vm_harness import VM,ROOT
with tempfile.TemporaryDirectory() as temp:
    disk=Path(temp)/'disk.img';shutil.copyfile(ROOT/'build/asfs4.img',disk)
    vm=VM(Path(temp),disk,memory=200)
    try:
        initial=vm.cmd('mousestat')
        assert 'x=480 y=300 botones=0' in initial,initial
        vm.qmp('human-monitor-command',{'command-line':'mouse_move -50 60'})
        time.sleep(.15)
        moved=vm.cmd('mousestat')
        assert 'x=430 y=360 botones=0' in moved,moved
        vm.qmp('human-monitor-command',{'command-line':'mouse_button 1'})
        time.sleep(.15)
        clicked=vm.cmd('mousestat')
        assert 'x=430 y=360 botones=1' in clicked,clicked
        vm.qmp('human-monitor-command',{'command-line':'mouse_button 0'})
        vm.cmd('echo teclado-ok','teclado-ok')
        vm.cmd('touch /mousefile')
        before=len(vm.out());vm.type('desktop');vm.key('ret')
        vm.qmp('human-monitor-command',{'command-line':'mouse_move -280 -105'})
        time.sleep(.15)
        vm.qmp('human-monitor-command',{'command-line':'mouse_button 0'})
        time.sleep(.15)
        vm.qmp('human-monitor-command',{'command-line':'mouse_button 1'})
        time.sleep(.2)
        vm.qmp('human-monitor-command',{'command-line':f'screendump {Path(temp)/"mouse-window.ppm"}'})
        ppm=(Path(temp)/'mouse-window.ppm').read_bytes()
        raw=ppm.split(b'\n',3)[3]
        width=int(ppm.split(b'\n',3)[1].split()[0])
        color=raw[(206*width+350)*3:(206*width+350)*3+3]
        assert color==bytes.fromhex('2976a4'),color
        vm.key('esc');vm.key('esc')
        vm.wait('asm:/ > ',before)
        vm.cmd('ls','mousefile')
    finally:vm.close()
print('Mouse PS/2: movimiento, clic, teclado y escritorio OK.')
