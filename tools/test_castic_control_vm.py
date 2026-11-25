"""Castic control flow and invalid input under the real i386 kernel."""
import tempfile
from pathlib import Path
from fs_format import fresh,put,seal,SIZE
from vm_harness import VM
cases={
 'loop.cas':(b'int a = 0; while (a < 5) { a += 1; } return a;',5),
 'skip.cas':(b'int a = 3; while (a < 1) { a += 10; } if (a == 3) { a += 4; } if (a != 7) { a += 50; } return a;',7),
 'nest.cas':(b'int a = 0; int b = 0; while (a < 3) { a += 1; b += 2; if (a >= 2) { b += 1; } } return b;',8),
 'cmp.cas':(b'int a = 4; if (a <= 4) { a += 1; } if (a > 4) { a += 2; } if (a >= 8) { a += 30; } return a;',7),
 'last.cas':(b'int a = 1; if (a == 0) { a += 1; }',0),
}
bad={'unclosed.cas':b'int a = 1; while (a < 3) { a += 1;', 'close.cas':b'int a = 1; } return a;', 'undef.cas':b'if (a == 0) { print no; }', 'decl.cas':b'int a = 1; if (a == 1) { int b = 1; } return a;', 'badop.cas':b'int a = 1; if (a = 1) { a += 1; } return a;'}
with tempfile.TemporaryDirectory() as tmp:
 p=Path(tmp);disk=p/'disk.img';fs=fresh()
 for i,(name,(source,_)) in enumerate(cases.items(),70):put(fs,i,name,source)
 for i,(name,source) in enumerate(bad.items(),80):put(fs,i,name,source)
 seal(fs);raw=bytearray(32*1024*1024);raw[:SIZE]=fs;raw[8192*512:8192*512+SIZE]=fs;disk.write_bytes(raw)
 v=VM(p,disk,memory=256)
 try:
  for name,(_,result) in cases.items():
   app=name[:-4]+'.app';v.cmd('castic '+name+' '+app,'compilado i386 AX05');v.cmd('exec '+app,'Programa termino. EAX='+str(result))
  for name in bad:v.cmd('castic '+name+' bad.app','sintaxis invalida')
 finally:v.close()
print('OK: while, nesting, six unsigned comparisons, skipped blocks, syntax rejection.')
