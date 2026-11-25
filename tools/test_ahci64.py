"""AHCI SATA x64: probe and HSFS6 reads; never modify attached image."""
import json, os, select, shlex, subprocess, tempfile, time, hashlib
from pathlib import Path
from hsfs6 import mkfs, put
from vm_harness import ROOT

with tempfile.TemporaryDirectory() as tmp:
    p=Path(tmp);disk=p/'disk.img';src=p/'text';log=p/'qemu.log'
    mkfs(disk,64*1024*1024);src.write_text('hola desde sata ahci\n');put(disk,'sata.txt',src)
    put(disk,'nuevo.txt',src)
    original=hashlib.sha256(disk.read_bytes()).digest()
    cmd=['qemu-system-x86_64','-m','256','-accel','tcg','-display','none','-serial','none',
         '-monitor','none','-nic','none','-no-reboot','-boot','d','-cdrom',
         str(ROOT/'dist/CastiOS-x64-preview.iso'),'-device','ich9-ahci,id=sata',
         '-drive',f'file={disk},format=raw,if=none,id=satadisk',
         '-device','ide-hd,drive=satadisk,bus=sata.0','-qmp','stdio',f'-debugcon',f'file:{log}']
    cmd+=shlex.split(os.environ.get('QEMU_EXTRA_ARGS',''))
    vm=subprocess.Popen(cmd,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,bufsize=0)
    def read():
        assert select.select([vm.stdout],[],[],15)[0], 'QMP timeout'
        return json.loads(vm.stdout.readline())
    def qmp(name,args=None):
        obj={'execute':name}
        if args:obj['arguments']=args
        vm.stdin.write(json.dumps(obj).encode()+b'\n')
        while True:
            r=read();assert 'error' not in r,r
            if 'return' in r:return
    def wait(text,offset=0):
        for _ in range(750):
            content=log.read_text(errors='replace') if log.exists() else ''
            if text in content[offset:]:return
            time.sleep(.02)
        raise AssertionError((text,content[-1000:]))
    def command(text,expected):
        start=len(log.read_text())
        for c in text:
            key={' ':'spc','.':'dot','>':'shift-dot'}.get(c,c)
            qmp('human-monitor-command',{'command-line':f'sendkey {key} 30'});time.sleep(.012)
        qmp('human-monitor-command',{'command-line':'sendkey ret 30'});wait(expected,start)
    try:
        read();qmp('qmp_capabilities');wait('x64> ')
        command('ahciscan','AHCI SATA listo (solo lectura)')
        command('mount','HSFS6 montado')
        command('ls','sata.txt')
        command('cat sata.txt','hola desde sata ahci')
        command('filesys','Proceso CPL3 terminado con EAX=7')
        command('echo prueba > sata.txt','error ATA o FLUSH')
        command('uname','long mode activo')
    finally:vm.terminate();vm.wait(timeout=5)
    assert hashlib.sha256(disk.read_bytes()).digest()==original
print('AHCI x64: deteccion PCI, DMA, lectura HSFS6 y bloqueo escritura OK')
