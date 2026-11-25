"""Exercise C-like declarations and actual int 80h from compiled Castic."""
import shutil, tempfile
from pathlib import Path
from fs_format import SIZE, extract_or_migrate, put, seal
from vm_harness import ROOT, VM
with tempfile.TemporaryDirectory() as tmp:
 p=Path(tmp); disk=p/'disk.img'; shutil.copyfile(ROOT/'build/CastiOS-hdd.img',disk)
 with disk.open('r+b') as f:
  f.seek(16*1024*1024); fs=extract_or_migrate(f.read(SIZE))
  put(fs,234,'func.cas',b'fn f { a += 2; } int a = 3; f(); f(); return a;',kind=1)
  put(fs,235,'recur.cas',b'fn f { f(); } f();',kind=1)
  put(fs,236,'missing.cas',b'z();',kind=1)
  put(fs,230,'csyn.cas',b'int a = 7; a += 5; a *= 3; a /= 2; a -= 1; return a;',kind=1)
  put(fs,231,'pid.cas',b'syscall(3,0,0,0,a); return a;',kind=1)
  put(fs,232,'badptr.cas',b'syscall(5,0,1,0,a); return a;',kind=1)
  put(fs,233,'bad.cas',b'syscall(3,0,0,0,z; return z;',kind=1)
  seal(fs)
  for off in (16*1024*1024,20*1024*1024):f.seek(off);f.write(fs)
 v=VM(p,disk,memory=200)
 try:
  for source,out,expect in [('func.cas','func.app','7'),('csyn.cas','csyn.app','17'),('pid.cas','pid.app','1'),('badptr.cas','badptr.app','4294967282')]:
   v.cmd('castic '+source+' '+out,'compilado i386 AX05')
   v.cmd('exec '+out,'Programa termino. EAX='+expect)
  v.cmd('castic recur.cas recur.app','sintaxis invalida')
  v.cmd('castic missing.cas missing.app','sintaxis invalida')
  v.cmd('castic bad.cas bad.app','sintaxis invalida')
  v.cmd('exec bad.app','no existe')
 finally:v.close()
print('Castic i386: int declarations, syscall result, EFAULT and syntax OK')
