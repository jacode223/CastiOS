"""Targeted wait reuses a freed slot without reusing a live PID."""
import shutil,struct,tempfile
from pathlib import Path
from fs_format import SIZE,extract_or_migrate,put,seal
from vm_harness import VM,ROOT

def mov(reg,n):return bytes([0xb8+reg])+struct.pack('<I',n)
def app(code):return b'AX05'+struct.pack('<I',len(code))+code
slow=mov(3,10000)+mov(0,18)+b'\xcd\x80'+mov(0,77)+b'\xc3'
fast=mov(0,42)+b'\xc3'
pid=mov(0,3)+b'\xcd\x80\xc3'
with tempfile.TemporaryDirectory() as t:
 work=Path(t);disk=work/'disk.img';shutil.copyfile(ROOT/'build/CastiOS-hdd.img',disk)
 with disk.open('r+b') as f:
  f.seek(16*1024*1024);fs=extract_or_migrate(f.read(SIZE))
  for i,(name,code) in enumerate((('slow.app',slow),('fast.app',fast),('pid.app',pid)),230):
   put(fs,i,name,app(code),kind=3)
  fs=seal(fs)
  for off in (16*1024*1024,20*1024*1024):f.seek(off);f.write(fs)
 v=VM(work,disk,memory=200)
 try:
  v.cmd('bg slow.app','Proceso de fondo iniciado: 1')
  v.cmd('bg slow.app','Proceso de fondo iniciado: 2')
  v.cmd('bg fast.app','Proceso de fondo iniciado: 3')
  v.cmd('wait 3','Proceso 3 EAX=42')
  v.cmd('bg fast.app','Proceso de fondo iniciado: 4')
  listing=v.cmd('ps')
  assert 'Proceso 4' in listing and 'Proceso 3 ' not in listing,listing
  v.cmd('kill 3','Uso: kill PID')
  v.cmd('wait 4','Proceso 4 EAX=42')
  v.cmd('kill 1','Proceso detenido: 1')
  v.cmd('wait 1','Proceso 1 EAX=143')
  v.cmd('kill 2','Proceso detenido: 2')
  v.cmd('wait 2','Proceso 2 EAX=143')
  v.cmd('ps','Sin procesos de fondo')
  v.cmd('bg pid.app','Proceso de fondo iniciado: 5')
  v.cmd('wait 5','Proceso 5 EAX=5')
  v.cmd('echo shell-viva','shell-viva')
 finally:v.close()
print('wait PID: ranura reutilizada, PID no reciclado, kill obsoleto rechazado y getpid OK.')
