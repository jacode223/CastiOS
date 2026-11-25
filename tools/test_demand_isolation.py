"""Automatic bounded AX05 pages, read-only code, fault cleanup and isolation."""
import re, shutil, struct, tempfile
from pathlib import Path
from fs_format import COUNT,RECORD,SIZE,extract_or_migrate,put,seal
from vm_harness import VM,ROOT

def mov(r,n):return bytes([0xb8+r])+struct.pack('<I',n)
def app(code):return b'AX05'+struct.pack('<I',len(code))+code+b''
def store(addr,value):return mov(0,addr)+mov(3,value)+b'\x89\x18'
def load(addr):return mov(0,addr)+b'\x8b\x00'

with tempfile.TemporaryDirectory() as t:
 work=Path(t);disk=work/'disk.img';shutil.copyfile(ROOT/'build/CastiOS-hdd.img',disk)
 with disk.open('r+b') as f:
  f.seek(16*1024*1024);fs=extract_or_migrate(f.read(SIZE))
  free=(i for i in range(COUNT) if not fs[512+i*RECORD])
  programs={
   'divzero.app':mov(0,1)+mov(3,0)+mov(2,0)+b'\xf7\xf3\xc3',
   'heap.app':store(0x20008000,12345)+load(0x20008000)+b'\xc3',
   'fresh.app':load(0x20008000)+b'\xc3',
   'code.app':store(0x20000000,99)+b'\xc3',
   'guard.app':store(0x20001000,99)+b'\xc3',
   'kernel.app':store(0x10000,99)+b'\xc3',
   'wide.app':store(0x2000b000,77)+load(0x2000b000)+b'\xc3',
  }
  for name,code in programs.items():put(fs,next(free),name,app(code),kind=3)
  fs=seal(fs)
  for off in (16*1024*1024,20*1024*1024):f.seek(off);f.write(fs)
 v=VM(work,disk,memory=200)
 try:
  def free_kib():
   out=v.cmd('castctl mem');m=re.search(r'libres: (\d+) KiB',out)
   assert m,out
   return int(m.group(1))
  before=free_kib()
  v.cmd('exec heap.app','EAX=12345')
  v.cmd('exec fresh.app','EAX=0')
  for name in ('code.app','guard.app','kernel.app','divzero.app'):
   v.cmd('exec '+name,'EAX=4294967294')
  assert free_kib()==before,'fuga de páginas tras procesos terminados'
  v.cmd('bg heap.app','Proceso de fondo iniciado: 1')
  v.cmd('bg code.app','Proceso de fondo iniciado: 2')
  v.cmd('bg wide.app','Proceso de fondo iniciado: 3')
  v.cmd('bg divzero.app','Proceso de fondo iniciado: 4')
  result=v.cmd('wait','Proceso 4 terminado EAX=4294967294')
  assert 'Proceso 3 terminado EAX=77' in result,result
  assert 'Proceso 1 terminado EAX=12345' in result,result
  assert 'Proceso 2 terminado EAX=4294967294' in result,result
  after=free_kib()
  # Framebuffer history grows by one page as the test prints more lines.
  assert before-4<=after<=before,f'fuga en tareas de fondo: antes={before}, despues={after}'
  v.cmd('echo shell-viva','shell-viva')
 finally:v.close()
print('AX05: demanda, codigo RO, guardia, aislamiento, error de kernel y liberacion OK.')
