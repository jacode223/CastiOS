"""Disposable IDE installation, boot, persistence; VIA hardware not emulated."""
import tempfile
from pathlib import Path
from vm_harness import VM
with tempfile.TemporaryDirectory() as tmp:
 p=Path(tmp); disk=p/'disk.img'
 with disk.open('wb') as f:f.truncate(64*1024*1024)
 v=VM(p,disk,memory=256)
 try:
  start=len(v.out());v.type('install hda');v.key('ret');v.wait('FORMAT hda',start)
  v.type('FORMAT hda');v.key('ret');v.wait('Formateado e instalado',start);v.wait('asm:/ > ',start)
 finally:v.close()
 v=VM(p,disk,memory=256,boot_disk=True)
 try:v.cmd('castctl write prueba.txt persistencia','Guardado en disco')
 finally:v.close()
 v=VM(p,disk,memory=256,boot_disk=True)
 try:v.cmd('cat prueba.txt','persistencia')
 finally:v.close()
print('OK: install, boot and persistent file across restart on disposable IDE disk.')
