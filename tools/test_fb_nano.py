import tempfile,shutil
from pathlib import Path
from PIL import Image
from vm_harness import VM,ROOT
from fs_format import validate,body,RECORD
with tempfile.TemporaryDirectory() as t:
 p=Path(t);d=p/'data.img';shutil.copyfile(ROOT/'build/asfs4.img',d)
 v=VM(p,d)
 try:
  start=len(v.out());v.type('nano framebuffer.txt');v.key('ret');v.wait('ASM nano | ',start)
  v.type('Editor en framebuffer');v.key('ret');v.type('Linea 2: teclado y cursor')
  v.key('left');v.key('right');start=len(v.out());v.key('ctrl-o')
  v.wait('Buffer guardado',start)
  v.wait('Supr Borrar',start)
  import time;time.sleep(.3)
  out=ROOT/'build/fb-captures/nano.ppm';v.qmp('screendump',{'filename':str(out)})
  start=len(v.out());v.key('ctrl-x');v.wait('asm:/ > ',start)
  v.cmd('cat framebuffer.txt','Editor en framebuffer')
  # Backspace and command history remain usable.
  start=len(v.out());v.type('echo borrarr');v.key('backspace');v.key('ret');v.wait('borrar',start)
  v.key('up');v.key('ret');v.wait('asm:/ > ',start)
 finally:v.close()
 fs=validate(d.read_bytes())
 i=next(i for i in range(256) if fs[512+i*RECORD:512+i*RECORD+32].split(b'\0')[0]==b'framebuffer.txt')
 assert body(fs,i)==b'Editor en framebuffer\nLinea 2: teclado y cursor', repr(body(fs,i))
 Image.open(out).save(out.with_suffix('.png'))
print('OK: nano dibujado en framebuffer, edicion, guardado exacto, flechas, borrado e historial.')
