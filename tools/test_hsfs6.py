"""HSFS6 host copy-on-write and x64 reading, including data beyond 4 GiB."""
import json, os, re, select, shlex, subprocess, tempfile, time
from pathlib import Path
from hsfs6 import mkfs, put, mount, header, SECTOR, TABLE_LBA, HEADER_LBA
from vm_harness import ROOT

with tempfile.TemporaryDirectory() as tmp:
    p=Path(tmp);disk=p/'v.img';src=p/'s.txt';log=p/'log'
    mkfs(disk,6*1024**3)
    src.write_text('dato por encima de cuatro gigas\n')
    put(disk,'alto.txt',src,start_override=8388610)
    big=p/'grande.bin'
    with big.open('wb') as f:f.truncate(101*1024*1024+7)
    put(disk,'grande.bin',big)
    src.write_text('dato secreto')
    put(disk,'secreto.txt',src)
    import struct
    with disk.open('r+b') as f:
        generation,total,table,index=mount(f)
        slot=next(i for i in range(128) if table[i*128:i*128+12]==b'secreto.txt\0')
        struct.pack_into('<I',table,slot*128+76,0o600)
        f.seek(TABLE_LBA[index]*SECTOR);f.write(table)
        f.seek(HEADER_LBA[index]*SECTOR);f.write(header(generation,total,table,index))
    with disk.open('rb') as f:
        generation,total,table,index=mount(f)
        assert generation==3 and total>8388610
    cmd=['qemu-system-x86_64','-m','256','-accel','tcg','-display','none',
         '-serial','none','-monitor','none','-nic','none','-no-reboot','-boot','d',
         '-cdrom',str(ROOT/'dist/CastiOS-x64-preview.iso'),
         '-drive',f'file={disk},format=raw,if=ide,index=0','-qmp','stdio',
         f'-debugcon',f'file:{log}']+shlex.split(os.environ.get('QEMU_EXTRA_ARGS',''))
    vm=subprocess.Popen(cmd,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,bufsize=0)
    def read():
        assert select.select([vm.stdout],[],[],15)[0], 'QMP timeout'
        return json.loads(vm.stdout.readline())
    def qmp(command,args=None):
        d={'execute':command}
        if args:d['arguments']=args
        vm.stdin.write(json.dumps(d).encode()+b'\n')
        while True:
            r=read()
            assert 'error' not in r,r
            if 'return' in r:return
    def wait(text,offset=0):
        for _ in range(750):
            data=log.read_text(errors='replace') if log.exists() else ''
            if text in data[offset:]:return
            time.sleep(.02)
        raise AssertionError((text,data[-2000:]))
    def command(s,expected):
        start=len(log.read_text())
        for c in s:
            key={' ':'spc','.':'dot','/':'slash','>':'shift-dot'}.get(c,c)
            qmp('human-monitor-command',{'command-line':f'sendkey {key} 30'});time.sleep(.012)
        qmp('human-monitor-command',{'command-line':'sendkey ret 30'})
        wait(expected,start)
    try:
        read();qmp('qmp_capabilities');wait('x64> ')
        command('mount','HSFS6 montado')
        command('ls','alto.txt')
        command('cat alto.txt','dato por encima de cuatro gigas')
        command('stat grande.bin','bytes=105906183')
        command('cat missing','archivo inexistente')
        command('echo hola x64 > nuevo.txt','HSFS6: archivo guardado')
        command('cat nuevo.txt','hola x64')
        command('filesys','Proceso CPL3 terminado con EAX=7')
        command('filedeny','Proceso CPL3 terminado con EAX=7')
        command('filewrite','Proceso CPL3 terminado con EAX=7')
        command('fileguest','Proceso CPL3 terminado con EAX=7')
        command('cat desdeapp.txt','escrito por cpl3')
        command('echo segundo valor > nuevo.txt','HSFS6: archivo guardado')
        command('cat nuevo.txt','segundo valor')
        command('mount6','HSFS6 montado')
        command('cat6 nuevo.txt','segundo valor')
        command('write6 . prohibido','metadatos o nombre invalidos')
        command('cat6 nuevo.txt','HSFS6 no montado')
        command('mount6','HSFS6 montado')
        command('cat6 nuevo.txt','segundo valor')
    finally:
        vm.terminate();vm.wait(timeout=5)
    with disk.open('rb') as f:
        generation,_,table,index=mount(f)
        assert generation==6, generation
        record=next(table[i*128:(i+1)*128] for i in range(128) if table[i*128:i*128+10]==b'nuevo.txt\0')
        length,start=struct.unpack_from('<QQ',record,80)
        f.seek(start*512);assert f.read(length)==b'segundo valor\n'
    # If the latest slot is damaged, the previous committed snapshot remains readable.
    with disk.open('r+b') as f:
        f.seek((8+index)*SECTOR);f.write(b'BAD!');f.flush();os.fsync(f.fileno())
    with disk.open('rb') as f:
        generation,_,table,_=mount(f)
        assert generation==5 and table[0]
        record=next(table[i*128:(i+1)*128] for i in range(128) if table[i*128:i*128+10]==b'nuevo.txt\0')
        length,start=struct.unpack_from('<QQ',record,80)
        f.seek(start*512);assert f.read(length)==b'hola x64\n'
    # Simulate an interrupted update to the inactive metadata copy, then a
    # partial header: the previously committed generation remains mountable.
    with disk.open('r+b') as f:
        generation,_,_,active=mount(f)
        target=1-active
        f.seek(TABLE_LBA[target]*SECTOR);f.write(b'parcial')
        f.flush();os.fsync(f.fileno())
        assert mount(f)[0]==generation
        f.seek(HEADER_LBA[target]*SECTOR);f.write(b'HSFS6\0\0\0\x06')
        f.flush();os.fsync(f.fileno())
        assert mount(f)[0]==generation
print('HSFS6: x64 read/write, >4 GiB, remount and interrupted metadata recovery OK')
