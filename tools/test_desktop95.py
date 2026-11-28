"""Boot the actual compiler and exercise the Win95 desktop."""
import tempfile,time
from pathlib import Path
from fs_format import fresh,put,seal
from vm_harness import VM, ROOT
from PIL import Image
with tempfile.TemporaryDirectory() as tmp:
 p=Path(tmp);fs=fresh()
 put(fs,61,'vars.cas',b'// comment\nint counter = 0; int Total = 7; while(counter < 3) { counter += 1; } syscall(0,0,0,0,Total); return counter;')
 seal(fs);disk=p/'disk.img'
 with disk.open('wb') as f:
  f.truncate(32*1024*1024);f.write(fs);f.seek(8192*512);f.write(fs)
 v=VM(p,disk,memory=256)
 try:
  v.cmd('castic vars.cas vars.app','compilado')
  v.cmd('exec vars.app','EAX=3')
  v.cmd('castic desk.cas desk.app','compilado')
  off=len(v.out());v.type('exec desk.app');v.key('ret');time.sleep(.6)
  def shot(name):
   out=ROOT/'build'/name;v.qmp('screendump',{'filename':str(out.with_suffix('.ppm'))})
   im=Image.open(out.with_suffix('.ppm'));im.save(out.with_suffix('.png'));return im
  im=shot('desktop95');assert im.getpixel((200,300))==(0,128,128),im.getpixel((200,300))
  assert im.getpixel((240,110))==(0,0,128)
  v.key('s');time.sleep(.2)
  im=shot('desktop95-menu');assert im.getpixel((10,430))==(0,0,128)
  v.key('s');v.key('c');time.sleep(.2)
  im=shot('desktop95-closed');assert im.getpixel((240,110))==(0,128,128)
  # Driver starts at 480,300: move to 50,50 and click desktop icon.
  for dx,dy in [(-100,-100),(-100,-100),(-100,-50),(-100,0),(-30,0)]:
   v.qmp('input-send-event',{'events':[{'type':'rel','data':{'axis':'x','value':dx}},{'type':'rel','data':{'axis':'y','value':dy}}]});time.sleep(.05)
  v.qmp('input-send-event',{'events':[{'type':'btn','data':{'down':True,'button':'left'}}]});time.sleep(.2)
  im=shot('desktop95-click');assert im.getpixel((240,110))==(0,0,128)
  v.key('q');v.wait('EAX=0',off)
 finally:v.close()
print('OK: named variables, loop, desktop, Start, close, mouse icon, exit')
