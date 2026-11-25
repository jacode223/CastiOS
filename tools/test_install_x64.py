"""Boot a new x64 BIOS disk, write HSFS6, reboot, and check persistence."""
import json, os, select, shlex, subprocess, tempfile, time
from pathlib import Path
from install_x64_image import create
from vm_harness import ROOT

with tempfile.TemporaryDirectory() as tmp:
    p=Path(tmp);disk=p/'hdd.img';create(disk,64*1024*1024)
    try:create(disk,64*1024*1024)
    except FileExistsError:pass
    else:raise AssertionError('Refused to protect an existing image')
    def run(second):
        log=p/('second.log' if second else 'first.log')
        cmd=['qemu-system-x86_64','-accel','tcg','-display','none','-serial','none',
             '-monitor','none','-nic','none','-no-reboot','-boot','c',
             '-drive',f'file={disk},format=raw,if=ide,index=0','-qmp','stdio',
             f'-debugcon',f'file:{log}']+shlex.split(os.environ.get('QEMU_EXTRA_ARGS',''))
        vm=subprocess.Popen(cmd,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,bufsize=0)
        def read():
            assert select.select([vm.stdout],[],[],15)[0]
            return json.loads(vm.stdout.readline())
        def qmp(name,args=None):
            d={'execute':name}
            if args:d['arguments']=args
            vm.stdin.write(json.dumps(d).encode()+b'\n')
            while True:
                r=read();assert 'error' not in r,r
                if 'return' in r:return
        def wait(s,start=0):
            for _ in range(1000):
                t=log.read_text(errors='replace') if log.exists() else ''
                if s in t[start:]:return
                time.sleep(.02)
            raise AssertionError((s,t[-1200:]))
        def command(s,expected):
            start=len(log.read_text())
            for c in s:
                key={' ':'spc','.':'dot','>':'shift-dot'}.get(c,c)
                qmp('human-monitor-command',{'command-line':f'sendkey {key} 30'});time.sleep(.012)
            qmp('human-monitor-command',{'command-line':'sendkey ret 30'});wait(expected,start)
        try:
            read();qmp('qmp_capabilities');wait('long mode activo\nx64> ')
            command('disks','IDE hda: sectores=131072')
            wait('Lecturas fallidas=0 reintentos=0')
            command('mount','HSFS6 montado')
            if not second:
                command('echo persistencia > prueba.txt','HSFS6: archivo guardado')
                command('disks','IDE hda: sectores=131072')
            command('cat prueba.txt','persistencia')
        finally:vm.terminate();vm.wait(timeout=5)
    run(False);run(True)
    # Perform a real in-guest installation to a distinct blank disk image.
    guestdisk=p/'guest.img'
    with guestdisk.open('wb') as f:f.truncate(64*1024*1024)
    log=p/'installer.log'
    cmd=['qemu-system-x86_64','-accel','tcg','-display','none','-serial','none',
         '-monitor','none','-nic','none','-no-reboot','-boot','d',
         '-cdrom',str(ROOT/'dist/CastiOS-x64-preview.iso'),
         '-drive',f'file={guestdisk},format=raw,if=ide,index=0','-qmp','stdio',
         f'-debugcon',f'file:{log}']+shlex.split(os.environ.get('QEMU_EXTRA_ARGS',''))
    vm=subprocess.Popen(cmd,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,bufsize=0)
    def read():
        assert select.select([vm.stdout],[],[],15)[0]
        return json.loads(vm.stdout.readline())
    def qmp(name,args=None):
        d={'execute':name}
        if args:d['arguments']=args
        vm.stdin.write(json.dumps(d).encode()+b'\n')
        while True:
            r=read();assert 'error' not in r,r
            if 'return' in r:return
    def wait(text,start=0):
        for _ in range(2000):
            t=log.read_text(errors='replace') if log.exists() else ''
            if text in t[start:]:return
            time.sleep(.02)
        raise AssertionError((text,t[-1200:]))
    def command(text,expected):
        start=len(log.read_text())
        for c in text:
            key={' ':'spc','.':'dot','>':'shift-dot'}.get(c,c)
            qmp('human-monitor-command',{'command-line':f'sendkey {key} 30'});time.sleep(.012)
        qmp('human-monitor-command',{'command-line':'sendkey ret 30'});wait(expected,start)
    try:
        read();qmp('qmp_capabilities');wait('long mode activo\nx64> ')
        command('install','BORRA TODO hda IDE')
        with guestdisk.open('rb') as f:assert f.read(512)==bytes(512)
        command('install hda borrar','Instalacion BIOS terminada')
    finally:vm.terminate();vm.wait(timeout=5)
    disk=guestdisk
    run(False);run(True)
print('x64: instalacion en imagen, arranque BIOS, discos y persistencia OK')
