"""Apply the exact release kernel from an older disposable installed disk."""
import tempfile,shutil
from pathlib import Path
from fs_format import COUNT,RECORD,SIZE,extract_or_migrate,put,seal
from vm_harness import VM,ROOT
with tempfile.TemporaryDirectory() as tmp:
 p=Path(tmp); disk=p/'disk.img';shutil.copyfile(ROOT/'build/CastiOS-hdd.img',disk)
 kernel=(ROOT/'build/kernel.bin').read_bytes()
 with disk.open('r+b') as f:
  f.seek(16*1024*1024);fs=extract_or_migrate(f.read(SIZE));free=(i for i in range(COUNT) if not fs[512+i*RECORD])
  put(fs,next(free),'new.img',kernel,kind=3)
  put(fs,next(free),'control.cas',b'int a = 0; while (a < 3) { a += 1; } return a;',kind=1)
  seal(fs)
  for offset in (16*1024*1024,20*1024*1024):f.seek(offset);f.write(fs)
 v=VM(p,disk,boot_disk=True,memory=256)
 try:v.cmd('castctl kapply new.img','Kernel nuevo verificado y seleccionado')
 finally:v.close()
 v=VM(p,disk,boot_disk=True,memory=256)
 try:
  v.cmd('castic control.cas control.app','compilado i386 AX05')
  v.cmd('exec control.app','Programa termino. EAX=3')
  v.cmd('castctl kaccept','Kernel nuevo confirmado')
 finally:v.close()
 v=VM(p,disk,boot_disk=True,memory=256)
 try:v.cmd('exec control.app','Programa termino. EAX=3')
 finally:v.close()
print('OK: exact release kernel A/B update, test boot, accept, reboot and Castic loop.')
