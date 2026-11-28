"""Named Castic UI functions and mouse interaction under QEMU."""
import tempfile,time
from pathlib import Path
from fs_format import fresh,put,seal
from vm_harness import VM, ROOT
with tempfile.TemporaryDirectory() as tmp:
 p=Path(tmp);fs=fresh()
 put(fs,60,'widgets.cas',(ROOT/'examples/castic/widgets.cas').read_bytes())
 put(fs,61,'names.cas',b'fn apple { a += 1; } fn apricot { a += 2; } int a = 0; apple(); apricot(); return a;')
 put(fs,62,'badname.cas',b'fn apple { print hi; } app();')
 seal(fs);disk=p/'disk.img'
 with disk.open('wb') as f:
  f.truncate(32*1024*1024);f.write(fs);f.seek(8192*512);f.write(fs)
 v=VM(p,disk,memory=256)
 try:
  v.cmd('castic names.cas names.app','compilado')
  v.cmd('exec names.app','EAX=3')
  v.cmd('castic badname.cas bad.app','sintaxis invalida')
  v.cmd('castic widgets.cas widgets.app','compilado')
  off=len(v.out());v.type('exec widgets.app');v.key('ret');time.sleep(.4)
  for dx,dy in [(-100,-100),(-100,-40),(-100,0)]:
   v.qmp('input-send-event',{'events':[{'type':'rel','data':{'axis':'x','value':dx}},{'type':'rel','data':{'axis':'y','value':dy}}]})
   time.sleep(.1)
  v.qmp('input-send-event',{'events':[{'type':'btn','data':{'down':True,'button':'left'}}]})
  time.sleep(.3)
  out=ROOT/'build/widgets.ppm';v.qmp('screendump',{'filename':str(out)})
  from PIL import Image
  im=Image.open(out)
  colors=im.crop((140,220,172,236)).getcolors()
  assert any(rgb==(22,115,104) for _,rgb in colors),colors
  v.key('q');v.wait('EAX=113',off)
 finally:v.close()
print('OK: named functions, exact lookup, widgets compile, click draws label, quit')
