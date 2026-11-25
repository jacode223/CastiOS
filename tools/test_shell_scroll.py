import tempfile,subprocess,struct,os
from pathlib import Path
from vm_harness import VM,ROOT
from PIL import Image
subprocess.run(['nasm','-f','bin','-w-reloc-abs-word','-w-reloc-abs-dword','-l','build/scroll.lst','src/kernel.asm','-o','build/scroll-check.bin'],cwd=ROOT,check=True)
assert (ROOT/'build/scroll-check.bin').read_bytes()==(ROOT/'build/kernel.bin').read_bytes()
listing=(ROOT/'build/scroll.lst').read_text()
def symbol(name):
 for line in listing.splitlines():
  if name+' dd ' in line or name+' times ' in line:
   words=line.split()
   for x in words[1:]:
    if len(x)==8 and all(c in '0123456789ABCDEF' for c in x):return int(x,16)+0x10000
 raise AssertionError(name)
with tempfile.TemporaryDirectory() as t:
 p=Path(t);v=VM(p,memory=32)
 def memory(addr,size):
  f=p/'mem.bin';v.qmp('human-monitor-command',{'command-line':f'pmemsave {addr} {size} "{f}"'});return f.read_bytes()
 def state(n):return struct.unpack('<I',memory(symbol(n),4))[0]
 try:
  assert state('history_capacity')<=16
  v.cmd('uname','CastiOS')
  assert 'desconocido' not in v.cmd('ls')
  for i in range(30):
   v.cmd('help')
   if state('history_count')==256:break
  assert state('history_count')==256,(state('history_count'),state('history_capacity'))
  assert state('history_capacity')==256
  live=memory(symbol('term_cells'),4000)
  v.key('pgup')
  import time;time.sleep(.3)
  assert state('history_offset')==12
  assert memory(symbol('term_cells'),4000)==live
  v.qmp('screendump',{'filename':str(ROOT/'build/shell-history.ppm')})
  for i in range(24):v.key('pgup')
  time.sleep(.3);assert state('history_offset')==256
  v.key('pgdn');time.sleep(.2);assert state('history_offset')==244
  v.type('e');time.sleep(.2);assert state('history_offset')==0
  v.type('cho regreso');start=len(v.out());v.key('ret');v.wait('regreso',start);v.wait('asm:/ > ',start)
  v.cmd('clear')
  v.cmd('echo Shell bitmap optimizada')
  v.qmp('screendump',{'filename':str(ROOT/'build/shell-live.ppm')})
  v.cmd('castctl memtest','Memoria: OK')
 finally:v.close()
for name in ['shell-live','shell-history']:
 Image.open(ROOT/'build'/(name+'.ppm')).save(ROOT/'build'/(name+'.png'))
print('OK: historial bajo demanda, ring 256, PgUp/PgDn y retorno al escribir.')
