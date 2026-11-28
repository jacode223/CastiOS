"""PS/2 position/buttons and foreground input ABI through compiled Castic."""
import tempfile
from pathlib import Path
from fs_format import fresh, put, seal, SIZE
from vm_harness import VM
cases = {
 'mx': 'syscall(25,0,0,0,a); return a;',
 'my': 'syscall(25,1,0,0,a); return a;',
 'mb': 'syscall(25,2,0,0,a); return a;',
 'mp': 'syscall(25,3,0,0,a); return a;',
 'bad': 'syscall(25,5,0,0,a); return a;',
 'event': 'int a = 0; while (a != 137) { syscall(26,0,0,0,a); } syscall(25,2,0,0,b); return b;',
 'key': 'int a = 0; while (a != 113) { syscall(26,0,0,0,a); } return a;',
 'lib': 'use desk; int x = 0; int y = 0; int v = 0; m(); return x;',
}
with tempfile.TemporaryDirectory() as temporary:
 work = Path(temporary);disk = work/'test.img';fs = fresh()
 for i,(name,body) in enumerate(cases.items(),60):
  put(fs,i,name+'.cas',body.encode())
 seal(fs)
 with disk.open('wb') as f:
  f.truncate(32*1024*1024);f.write(fs);f.seek(8192*512);f.write(fs)
 vm = VM(work,disk,memory=256)
 try:
  for name in cases:vm.cmd('castic '+name+'.cas '+name+'.app','compilado')
  vm.cmd('exec mp.app','EAX=1')
  vm.cmd('exec mx.app','EAX=480')
  vm.cmd('exec my.app','EAX=300')
  vm.cmd('exec bad.app','EAX=4294967274')
  vm.qmp('input-send-event',{'events':[
   {'type':'rel','data':{'axis':'x','value':20}},
   {'type':'rel','data':{'axis':'y','value':10}}]})
  vm.cmd('exec mx.app','EAX=500')
  vm.cmd('exec my.app','EAX=310')
  vm.cmd('exec lib.app','EAX=500')
  off=len(vm.out());vm.type('exec event.app');vm.key('ret')
  vm.qmp('input-send-event',{'events':[{'type':'btn','data':{'down':True,'button':'left'}}]})
  vm.wait('EAX=1',off);vm.wait('asm:/ > ',off)
  vm.cmd('exec mb.app','EAX=1')
  vm.qmp('input-send-event',{'events':[{'type':'btn','data':{'down':False,'button':'left'}}]})
  vm.cmd('exec mb.app','EAX=0')
  off=len(vm.out());vm.type('exec key.app');vm.key('ret');vm.key('q')
  vm.wait('EAX=113',off);vm.wait('asm:/ > ',off)
  vm.cmd('echo entrada-ok','entrada-ok')
 finally:vm.close()
print('OK: PS/2 coordinates, buttons, library, events, bounds and keyboard restored')
