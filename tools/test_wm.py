"""Overlapping windows retain state, focus, move and close independently."""
import tempfile,shutil,time
from pathlib import Path
from vm_harness import VM,ROOT
with tempfile.TemporaryDirectory() as tmp:
 p=Path(tmp);disk=p/'d.img';shutil.copyfile(ROOT/'build/asfs4.img',disk)
 v=VM(p,disk,memory=200)
 try:
  v.type('desktop');v.key('ret');v.key('down');v.key('ret')
  v.key('down');v.key('down');v.key('ret') # Files enters docs
  v.key('tab');v.key('down');v.key('down');v.key('down');v.key('ret') # System
  def color(x,y):
   v.qmp('human-monitor-command',{'command-line':f'screendump {p/"wm.ppm"}'})
   chunks=(p/'wm.ppm').read_bytes().split(b'\n',3);w=int(chunks[1].split()[0]);return chunks[3][(y*w+x)*3:(y*w+x)*3+3]
  assert color(500,230)==bytes.fromhex('2976a4') # active System title
  v.key('ctrl-n') # focus Files, raised above System
  assert color(700,210)==bytes.fromhex('2976a4')
  v.key('a');v.key('w') # move Files
  assert color(700,194)==bytes.fromhex('2976a4')
  v.key('ctrl-w');v.key('ctrl-w');start=len(v.out());v.key('esc');v.wait('asm:/ > ',start)
  v.cmd('pwd','/docs/')
  v.cmd('echo wm-ok','wm-ok')
 finally:v.close()
print('WM: ventanas simultaneas, foco, movimiento, cierre y carpeta conservada OK.')
