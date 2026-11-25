"""Stop a sleeping AX05 job; reclaim demand/swap resources and keep shell alive."""
import re,shutil,struct,tempfile
from pathlib import Path
from fs_format import SIZE,extract_or_migrate,put,seal
from vm_harness import VM,ROOT

def mov(reg,n):return bytes([0xb8+reg])+struct.pack('<I',n)
def app(code):return b'AX05'+struct.pack('<I',len(code))+code
sleeping=(mov(0,15)+b'\xcd\x80'+mov(0,16)+b'\xcd\x80'+
          mov(0,0x20008000)+mov(3,77)+b'\x89\x18'+
          mov(3,10000)+mov(0,18)+b'\xcd\x80'+mov(0,77)+b'\xc3')
done=mov(0,42)+b'\xc3'
spinning=mov(1,0x7fffffff)+b'\x49\x75\xfd'+mov(0,99)+b'\xc3'
with tempfile.TemporaryDirectory() as t:
 work=Path(t);disk=work/'disk.img';shutil.copyfile(ROOT/'build/CastiOS-hdd.img',disk)
 with disk.open('r+b') as f:
  f.seek(16*1024*1024);fs=extract_or_migrate(f.read(SIZE))
  put(fs,230,'sleep.app',app(sleeping),kind=3)
  put(fs,231,'done.app',app(done),kind=3)
  put(fs,232,'spin.app',app(spinning),kind=3)
  fs=seal(fs)
  for off in (16*1024*1024,20*1024*1024):f.seek(off);f.write(fs)
 v=VM(work,disk,memory=200)
 try:
  def memory():
   output=v.cmd('castctl mem');m=re.search(r'libres: (\d+) KiB',output)
   assert m,output
   return int(m.group(1))
  before=memory()
  v.cmd('kill 1','Sin procesos de fondo')
  v.cmd('bg sleep.app','Proceso de fondo iniciado: 1')
  v.cmd('ps','durmiendo')
  v.cmd('kill 5','Uso: kill PID')
  v.cmd('kill 1','Proceso detenido: 1')
  v.cmd('ps','Proceso 1 terminado EAX=143')
  v.cmd('kill 1','ya termino')
  v.cmd('wait','Proceso 1 terminado EAX=143')
  assert memory()>=before-4,'paginas de la tarea detenida no liberadas'
  v.cmd('bg spin.app','Proceso de fondo iniciado: 2')
  v.cmd('ps','Proceso 2 ejecutando')
  v.cmd('kill 2','Proceso detenido: 2')
  v.cmd('wait','Proceso 2 terminado EAX=143')
  v.cmd('bg done.app','Proceso de fondo iniciado: 3')
  v.cmd('wait','Proceso 3 terminado EAX=42')
  v.cmd('echo shell-viva','shell-viva')
 finally:v.close()
print('kill: detiene bg dormida y en bucle, libera recursos, wait y nuevo bg funcionan.')
