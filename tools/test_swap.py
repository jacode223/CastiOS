"""Disk backed data page, isolated slots and background timed sleep."""
import shutil, struct, tempfile
from pathlib import Path
from fs_format import SIZE, extract_or_migrate, put, seal
from vm_harness import ROOT, VM

def mov(reg, value):
    return bytes([0xb8+reg])+struct.pack('<I', value)
call=b'\xcd\x80'
def app(sleep=False):
    # 'ABC' is in a permitted instruction immediate at USER_BASE+1.
    code=(mov(0,0x00434241)+mov(3,0x20000001)+mov(1,3)+mov(0,6)+call+
          mov(0,15)+call+mov(3,3)+mov(1,0x20004000)+mov(2,4)+mov(0,7)+call+
          mov(0,16)+call)
    if sleep: code+=mov(3,200)+mov(0,18)+call
    code+=(mov(0,17)+call+mov(3,0x20004000)+mov(1,3)+mov(0,5)+call+b'\xc3')
    return b'AX05'+struct.pack('<I',len(code))+code

with tempfile.TemporaryDirectory() as t:
    folder=Path(t);disk=folder/'disk.img';shutil.copyfile(ROOT/'build/CastiOS-hdd.img',disk)
    with disk.open('r+b') as f:
        f.seek(16*1024*1024);fs=extract_or_migrate(f.read(SIZE))
        put(fs,218,'swap.app',app(),kind=3)
        put(fs,219,'nap.app',app(True),kind=3)
        put(fs,220,'ABC',b'ABC',kind=1)
        out_only=mov(0,15)+call+mov(0,16)+call+b'\xc3'
        put(fs,221,'out.app',b'AX05'+struct.pack('<I',len(out_only))+out_only,kind=3)
        fs=seal(fs)
        for offset in (16*1024*1024,20*1024*1024):f.seek(offset);f.write(fs)
    v=VM(folder,disk,memory=200)
    try:
        result=v.cmd('exec swap.app','EAX=3')
        assert 'ABC' in result,result
        v.cmd('bg nap.app','Proceso de fondo iniciado: 1')
        v.cmd('bg nap.app','Proceso de fondo iniciado: 2')
        result=v.cmd('wait','Proceso 2 terminado EAX=3')
        assert 'Proceso 1 terminado EAX=3' in result and result.count('ABC')>=2,result
        v.cmd('echo vivo','vivo')
    finally:v.close()
    # A disk installed before the reservation may contain a large file at
    # the end. Never overwrite it, even if the new allocator avoids it.
    with disk.open('r+b') as f:
        f.seek(16*1024*1024);fs=bytearray(f.read(SIZE))
        o=512+222*8192
        fs[o:o+9]=b'old.large'
        struct.pack_into('<III',fs,o+32,0xffffffff,5,4096)
        cap=f.seek(0,2)//512
        struct.pack_into('<II',fs,o+48,cap-200-32768,8)
        fs=seal(fs)
        for off in (16*1024*1024,20*1024*1024):f.seek(off);f.write(fs)
        f.seek((cap-200)*512);f.write(b'X'*4096)
    v=VM(folder,disk,memory=200)
    try:v.cmd('exec out.app','EAX=4294967277')  # -ENODEV
    finally:v.close()
    with disk.open('rb') as f:
        f.seek((cap-200)*512)
        assert f.read(4096)==b'X'*4096
print('Swap: pagina de datos recuperada, dos slots aislados, sleep y shell OK.')
