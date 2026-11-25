"""Genera hello en una copia temporal, compila y prueba su callback read en QEMU."""
import json
import os
from pathlib import Path
import select
import shlex
import shutil
import subprocess
import tempfile
import time

root=Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix='driver-scaffold-') as directory:
    work=Path(directory)
    project=work/'project'
    shutil.copytree(root,project,ignore=shutil.ignore_patterns('dist','build','__pycache__'))
    subprocess.run(['python3','tools/new_driver.py','hello'],cwd=project,check=True)
    snapshot=(project/'src/kernel.asm').read_bytes()
    duplicate=subprocess.run(['python3','tools/new_driver.py','hello'],cwd=project,capture_output=True)
    assert duplicate.returncode != 0 and (project/'src/kernel.asm').read_bytes()==snapshot
    subprocess.run(['bash','build.sh'],cwd=project,check=True)
    log=work/'debug.log'
    args=[os.environ.get('QEMU','qemu-system-i386'),'-m','32','-accel','tcg','-boot','d',
          '-cdrom',str(project/'build/CastiOS.iso'),'-display','none','-nic','none',
          '-serial','none','-monitor','none','-qmp','stdio','-debugcon',f'file:{log}']
    with (work/'qemu.err').open('w') as err:
        p=subprocess.Popen(args+shlex.split(os.environ.get('QEMU_EXTRA_ARGS','')),
                           stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=err,bufsize=0)
        try:
            def read():
                assert select.select([p.stdout],[],[],15)[0]
                return json.loads(p.stdout.readline())
            read()
            def qmp(command,arguments=None):
                data={'execute':command}
                if arguments: data['arguments']=arguments
                p.stdin.write(json.dumps(data).encode()+b'\n')
                while True:
                    value=read()
                    assert 'error' not in value,value
                    if 'return' in value:return value['return']
            qmp('qmp_capabilities')
            def wait(text,offset=0):
                deadline=time.monotonic()+15
                while time.monotonic()<deadline:
                    if log.exists() and text in log.read_text()[offset:]:return
                    time.sleep(.03)
                raise AssertionError(log.read_text())
            def command(text,expected):
                start=log.stat().st_size
                for c in text+'\n':
                    key={' ':'spc','\n':'ret'}.get(c,c)
                    qmp('human-monitor-command',{'command-line':f'sendkey {key} 10'})
                    time.sleep(.024)
                wait('asm:/ > ',start)
                assert expected in log.read_text()[start:]
            wait('asm:/ > ')
            command('drivers','hello ready text')
            command('drvread hello','Driver hello listo')
            command('drvwrite hello prueba','error=2')
            command('drvtest','Driver API tests: OK')
        finally:
            p.terminate()
            try:p.wait(timeout=5)
            except subprocess.TimeoutExpired:p.kill();p.wait()
    print('OK: generador, proteccion ante duplicados, compilacion y driver hello en QEMU.')
(root/'docs/VALIDACION_DRIVERS.txt').write_text(
    'OK: driver generado hello registrado y probado en una ISO distinta en QEMU.\n'
    'OK: callback read retorna Driver hello listo; write ausente retorna ENOSYS.\n'
    'OK: nombres duplicados no sobreescriben el kernel.\n'
    'OK: drvtest comprueba ABI, duplicados, IRQ, ioctl y errores.\n',encoding='utf8')
