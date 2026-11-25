"""Exercise x64 ATA/HSFS against a disposable real disk and broken mirrors."""
import json
import os
from pathlib import Path
import select
import shlex
import shutil
import struct
import subprocess
import tempfile
import time
from fs_format import SIZE, extract_or_migrate, put, seal
from vm_harness import ROOT


def run(disk, expected):
    with tempfile.TemporaryDirectory() as tmp:
        log=Path(tmp)/'debug.log'
        args=['qemu-system-x86_64','-m','256','-accel','tcg','-display','none',
              '-serial','none','-monitor','none','-nic','none','-no-reboot',
              '-boot','d','-cdrom',str(ROOT/'dist/CastiOS-x64-preview.iso'),
              '-drive',f'file={disk},format=raw,if=ide,index=0',
              '-qmp','stdio','-debugcon',f'file:{log}']
        args+=shlex.split(os.environ.get('QEMU_EXTRA_ARGS',''))
        vm=subprocess.Popen(args,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,bufsize=0)
        def read():
            assert select.select([vm.stdout],[],[],15)[0], 'QMP timeout'
            return json.loads(vm.stdout.readline())
        def qmp(cmd,arguments=None):
            msg={'execute':cmd}
            if arguments:msg['arguments']=arguments
            vm.stdin.write(json.dumps(msg).encode()+b'\n')
            while True:
                r=read()
                if 'error' in r: raise AssertionError(r)
                if 'return' in r:return
        def wait(s, offset=0):
            for _ in range(1500):
                data=log.read_text(errors='replace') if log.exists() else ''
                if s in data[offset:]:return data[offset:]
                time.sleep(.02)
            raise AssertionError((s,data[-2000:]))
        def command(s, wanted):
            start=len(log.read_text())
            for ch in s:
                key={' ':'spc','.':'dot','/':'slash','-':'minus'}.get(ch,ch)
                qmp('human-monitor-command',{'command-line':f'sendkey {key} 30'})
                time.sleep(.012)
            qmp('human-monitor-command',{'command-line':'sendkey ret 30'})
            return wait(wanted,start)
        try:
            read();qmp('qmp_capabilities');wait('x64> ')
            command('mount',expected)
            if 'montado en solo lectura' in expected:
                command('ls /', 'docs/')
                command('cat /hello.txt', 'hola desde hsfs x64')
                command('cat /chain.txt', 'fin de cadena hsfs')
                command('cat /large.txt', 'archivo grande externo x64')
                command('cd /docs', 'x64> ')
                command('cat nota.txt','Carpetas persistentes')
                command('cd ..', 'x64> ')
                command('cat missing','ruta o archivo invalido')
                command('uname','long mode activo')
        finally:
            vm.terminate()
            try:vm.wait(timeout=5)
            except subprocess.TimeoutExpired:vm.kill();vm.wait()

with tempfile.TemporaryDirectory() as tmp:
    disk=Path(tmp)/'disk.img'
    shutil.copyfile(ROOT/'build/CastiOS-hdd.img',disk)
    with disk.open('r+b') as f:
        f.seek(16*1024*1024);fs=extract_or_migrate(f.read(SIZE))
        put(fs,230,'hello.txt',b'hola desde hsfs x64\n')
        put(fs,231,'chain.txt',b'A'*8000+b'fin de cadena hsfs\n')
        off=512+232*8192
        fs[off:off+10]=b'large.txt\0'
        body=b'archivo grande externo x64\n'
        struct.pack_into('<IIIIII',fs,off+32,0xffffffff,5,len(body),0,16384,1)
        seal(fs)
        for off in (16*1024*1024,20*1024*1024):f.seek(off);f.write(fs)
        f.seek((32768+16384)*512);f.write(body.ljust(512,b'\0'))
    run(disk,'HSFS5 montado en solo lectura, copia 1')
    with disk.open('r+b') as f:
        f.seek(16*1024*1024);f.write(b'BAD!')
    run(disk,'HSFS5 montado en solo lectura, copia 2')
    with disk.open('r+b') as f:
        f.seek(20*1024*1024);f.write(b'BAD!')
    run(disk,'HSFS5 no disponible')
print('x64 HSFS: IDE, copia primaria/espejo, rutas, lectura y rechazo OK.')
