"""Exercise the seven WM improvements through QMP keyboard/mouse and RGB output."""
import tempfile,shutil,time
from pathlib import Path
from vm_harness import VM,ROOT
with tempfile.TemporaryDirectory() as tmp:
 p=Path(tmp);disk=p/'d.img';shutil.copyfile(ROOT/'build/asfs4.img',disk)
 v=VM(p,disk,memory=200)
 try:
  def shot():
   time.sleep(.08)
   v.qmp('human-monitor-command',{'command-line':f'screendump {p/"wm.ppm"}'})
   chunks=(p/'wm.ppm').read_bytes().split(b'\n',3)
   return chunks[3]
  def pixel(raw,x,y):return raw[(y*1024+x)*3:(y*1024+x)*3+3]
  def check(x,y,rgb):
   raw=shot();assert pixel(raw,x,y)==bytes.fromhex(rgb),(x,y,pixel(raw,x,y),rgb)
  def enter():v.type('desktop');v.key('ret');time.sleep(.1)
  def leave():
   start=len(v.out());v.key('ctrl-q');v.wait('asm:/ > ',start)
  enter();v.key('down');v.key('ret') # Files at (290,95), size 630x430
  check(700,210,'2976a4')
  v.key('ctrl-y');check(700,210,'173b59') # minimized
  v.key('ctrl-r');check(700,210,'2976a4') # restored by keyboard
  v.key('ctrl-e');check(700,174,'2976a4') # maximized
  v.key('ctrl-e');check(700,210,'2976a4') # exact normal restore
  v.key('ctrl-z');check(960,400,'e5ebf2') # resized beyond former right edge
  v.key('ctrl-x');check(960,400,'173b59') # shrink
  v.key('a');v.key('w');check(700,194,'2976a4') # movement retained across desktop sessions
  before=shot();leave();enter();after=shot()
  assert before==after,'layout lost on desktop re-entry'
  # The taskbar restores a minimized window, with state and coordinates intact.
  v.key('ctrl-y')
  mx,my=480,300
  def move(x,y):
   global mx,my
   v.qmp('human-monitor-command',{'command-line':f'mouse_move {x-mx} {y-my}'})
   mx,my=x,y;time.sleep(.12)
  def button(n):
   v.qmp('human-monitor-command',{'command-line':f'mouse_button {n}'})
   time.sleep(.12)
  move(200,570);button(1);button(0);check(700,194,'2976a4')
  # No focus/hover change: moving the pointer only touches the cursor bounds.
  a=shot();move(400,300);b=shot()
  changed=sum(a[i:i+3]!=b[i:i+3] for i in range(0,len(a),3))
  assert 0<changed<=336,changed
  # Drag Files title 40 pixels left; normal location is now (274,79).
  move(400,100);button(1);move(360,100);button(0)
  check(300,194,'2976a4') # newly covered title area
  # Resize from the bottom-right grip without losing the folder state.
  move(234+624,79+424);button(1);move(234+650,79+450);button(0)
  check(32+234+640,400,'e5ebf2')
  leave();v.cmd('echo controles-ok','controles-ok')
 finally:v.close()
print('WM: minimizar/restaurar, barra, maximizar, tamaño, sesión, atajos, cursor parcial y arrastre OK.')
