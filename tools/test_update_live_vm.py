import tempfile
from pathlib import Path
from vm_harness import VM
with tempfile.TemporaryDirectory() as d:
 p=Path(d);disk=p/'disk.img'
 with disk.open('wb') as f:f.truncate(64*1024*1024)
 v=VM(p,disk,memory=256)
 try:
  start=len(v.out());v.type('install hda');v.key('ret');v.wait('FORMAT hda',start);v.type('FORMAT hda');v.key('ret');v.wait('Formateado e instalado',start);v.wait('asm:/ > ',start)
 finally:v.close()
 v=VM(p,disk,boot_disk=True,memory=256)
 try:v.cmd('castctl write persist.txt intacto','Guardado')
 finally:v.close()
 v=VM(p,disk,memory=256)
 try:
  v.cmd('cat persist.txt','intacto')
  v.cmd('update hda','Kernel nuevo verificado y seleccionado')
 finally:v.close()
 v=VM(p,disk,boot_disk=True,memory=256)
 try:
  v.cmd('cat persist.txt','intacto');v.cmd('castctl kaccept','Kernel nuevo confirmado')
 finally:v.close()
 v=VM(p,disk,boot_disk=True,memory=256)
 try:v.cmd('cat persist.txt','intacto')
 finally:v.close()
print('OK live update A/B, accept, reboot, file retained')
