import tempfile,os
from pathlib import Path
from vm_harness import VM,ROOT
from PIL import Image
folder=ROOT/'build/fb-captures';folder.mkdir(exist_ok=True)
with tempfile.TemporaryDirectory() as t:
 v=VM(Path(t))
 try:
  assert 'Framebuffer: RGB32 80x25 terminal activa' in v.out(),v.out()
  v.cmd('castctl console','Consola framebuffer: 1024x768 RGB32')
  v.cmd('help')
  v.qmp('screendump',{'filename':str(folder/'terminal.ppm')})
  v.cmd('clear')
  v.cmd('echo Terminal framebuffer funcionando')
  v.cmd('disks')
  v.qmp('screendump',{'filename':str(folder/'disks.ppm')})
  v.cmd('castctl memtest','Memoria: OK')
 finally:v.close()
for name in ('terminal','disks'):
 im=Image.open(folder/(name+'.ppm'));assert im.size==(1024,768),im.size
 colors=dict((rgb,count) for count,rgb in (im.getcolors(256) or []))
 assert 1000 < colors.get((216,226,240),0) < 200000, 'texto ausente o panel relleno incorrectamente'
 im.save(folder/(name+'.png'))
print('OK: framebuffer RGB32, shell, scroll, clear, memoria y capturas 1024x768.')
