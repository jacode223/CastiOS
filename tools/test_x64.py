"""Boot the independent x86-64 image and exercise its long-mode shell."""
import json
import os
import re
from pathlib import Path
import select
import shlex
import subprocess
import tempfile
import time

root=Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory() as tmp:
    log=Path(tmp)/'debug.log'
    cmd=['qemu-system-x86_64','-m','256','-accel','tcg','-display','none',
         '-serial','none','-monitor','none','-nic','none','-no-reboot','-boot','d',
         '-cdrom',str(root/'dist/CastiOS-x64-preview.iso'),'-qmp','stdio',
         '-debugcon','file:'+str(log)] + shlex.split(os.environ.get('QEMU_EXTRA_ARGS',''))
    vm=subprocess.Popen(cmd,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,bufsize=0)
    def read():
        assert select.select([vm.stdout],[],[],10)[0], 'QMP timeout'
        return json.loads(vm.stdout.readline())
    def qmp(name,arguments=None):
        obj={'execute':name}
        if arguments:obj['arguments']=arguments
        vm.stdin.write(json.dumps(obj).encode()+b'\n')
        while True:
            response=read()
            if 'error' in response:raise AssertionError(response)
            if 'return' in response:return response['return']
    def wait(needle):
        for _ in range(300):
            if needle in log.read_text(errors='replace'):return
            time.sleep(.03)
        raise AssertionError(log.read_text(errors='replace'))
    try:
        read();qmp('qmp_capabilities')
        wait('long mode activo\nx64> ')
        regs=qmp('human-monitor-command',{'command-line':'info registers'})
        assert 'EFER=' in regs and 'CS64' in regs,regs
        for key in 'mousestat':qmp('human-monitor-command',{'command-line':f'sendkey {key} 30'})
        qmp('human-monitor-command',{'command-line':'sendkey ret 30'})
        wait('PS/2 x=480 y=300 botones=0 eventos=0')
        qmp('human-monitor-command',{'command-line':'mouse_move 40 20'})
        qmp('human-monitor-command',{'command-line':'mouse_button 1'})
        time.sleep(.2)
        for key in 'mousestat':qmp('human-monitor-command',{'command-line':f'sendkey {key} 30'})
        qmp('human-monitor-command',{'command-line':'sendkey ret 30'})
        wait('PS/2 x=520 y=320 botones=1 eventos=')
        qmp('human-monitor-command',{'command-line':'mouse_button 0'})
        time.sleep(.2)
        for key in 'uname':
            qmp('human-monitor-command',{'command-line':f'sendkey {key} 30'})
        qmp('human-monitor-command',{'command-line':'sendkey ret 30'})
        wait('x64> uname\nCastiOS x86-64: long mode activo')
        for key in 'mem':qmp('human-monitor-command',{'command-line':f'sendkey {key} 30'})
        qmp('human-monitor-command',{'command-line':'sendkey ret 30'})
        wait('KiB sobre 1 MiB')
        for key in 'frames':qmp('human-monitor-command',{'command-line':f'sendkey {key} 30'})
        qmp('human-monitor-command',{'command-line':'sendkey ret 30'})
        wait('Marcos 4 KiB asignados: 14')
        for key in 'users':qmp('human-monitor-command',{'command-line':f'sendkey {key} 30'})
        qmp('human-monitor-command',{'command-line':'sendkey ret 30'})
        wait('root uid=0 gid=0; alice uid=1000 gid=100')
        for key in 'groups':qmp('human-monitor-command',{'command-line':f'sendkey {key} 30'})
        qmp('human-monitor-command',{'command-line':'sendkey ret 30'})
        wait('system gid=0; users gid=100')
        for key in 'rootcred':qmp('human-monitor-command',{'command-line':f'sendkey {key} 30'})
        qmp('human-monitor-command',{'command-line':'sendkey ret 30'})
        wait('x64> rootcred\nrecurso root:system permitido\nProceso CPL3 terminado con EAX=0')
        for key in 'guestcred':qmp('human-monitor-command',{'command-line':f'sendkey {key} 30'})
        qmp('human-monitor-command',{'command-line':'sendkey ret 30'})
        wait('x64> guestcred\nProceso CPL3 terminado con EAX=13')
        for key in 'groupcred':qmp('human-monitor-command',{'command-line':f'sendkey {key} 30'})
        qmp('human-monitor-command',{'command-line':'sendkey ret 30'})
        wait('x64> groupcred\nrecurso de grupo users permitido\nProceso CPL3 terminado con EAX=0')
        for key in 'multi64':qmp('human-monitor-command',{'command-line':f'sendkey {key} 30'})
        qmp('human-monitor-command',{'command-line':'sendkey ret 30'})
        wait('Cambio de tarea por PIT: ')
        output=log.read_text(errors='replace')
        assert 'tarea root completada' in output and 'tarea alice completada' in output,output
        match=re.search(r'Cambio de tarea por PIT: (\d+)',output)
        assert match and int(match.group(1))>0,output
        assert 'root EAX=11 alice EAX=22' in output,output
        for key in 'multifault64':qmp('human-monitor-command',{'command-line':f'sendkey {key} 30'})
        qmp('human-monitor-command',{'command-line':'sendkey ret 30'})
        wait('root EAX=11 alice EAX=4294967282')
        for key in 'run64':qmp('human-monitor-command',{'command-line':f'sendkey {key} 30'})
        qmp('human-monitor-command',{'command-line':'sendkey ret 30'})
        wait('Proceso CPL3 terminado con EAX=42')
        for key in 'fault64':qmp('human-monitor-command',{'command-line':f'sendkey {key} 30'})
        qmp('human-monitor-command',{'command-line':'sendkey ret 30'})
        wait('Tarea CPL3 terminada por fallo; kernel sigue')
        for key in 'badptr64':qmp('human-monitor-command',{'command-line':f'sendkey {key} 30'})
        qmp('human-monitor-command',{'command-line':'sendkey ret 30'})
        wait('x64> badptr64\nProceso CPL3 terminado con EAX=7')
        for key in 'ud64':qmp('human-monitor-command',{'command-line':f'sendkey {key} 30'})
        qmp('human-monitor-command',{'command-line':'sendkey ret 30'})
        wait('x64> ud64\nTarea CPL3 terminada por fallo; kernel sigue')
        for key in 'io64':qmp('human-monitor-command',{'command-line':f'sendkey {key} 30'})
        qmp('human-monitor-command',{'command-line':'sendkey ret 30'})
        wait('x64> io64\nTarea CPL3 terminada por fallo; kernel sigue')
        for key in 'uname':qmp('human-monitor-command',{'command-line':f'sendkey {key} 30'})
        qmp('human-monitor-command',{'command-line':'sendkey ret 30'})
        wait('x64> io64\nTarea CPL3 terminada por fallo; kernel sigue\nx64> uname\nCastiOS x86-64: long mode activo')
    finally:
        vm.terminate()
        try:vm.wait(timeout=5)
        except subprocess.TimeoutExpired:vm.kill();vm.wait()
print('x86-64: teclado, raton PS/2, multitarea, UID/GID y fallos OK.')
