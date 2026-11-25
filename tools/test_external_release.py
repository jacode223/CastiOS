import os,tempfile,hashlib
from pathlib import Path
from vm_harness import VM,ROOT
from test_external import fat_image
with tempfile.TemporaryDirectory() as t:
 p=Path(t);fat,_=fat_image(p,True);disk=ROOT/'build/CastiOS-hdd.img'
 before=hashlib.sha256(disk.read_bytes()).digest()
 v=VM(p,disk,boot_disk=True,slave=fat)
 try:
  v.cmd('console','framebuffer')
  v.cmd('nasm -v','NASM version 3.02')
  v.cmd('mount hdb1 /mnt/prueba','Montado FAT32')
  v.cmd('cat /mnt/prueba/HELLO.TXT','FAT32 externo funciona')
  v.cmd('font /mnt/prueba/MONO.TTF','TTF aplicada')
  v.cmd('font default','restaurada')
  v.cmd('umount /mnt/prueba','desmontado')
  v.cmd('memtest','Memoria: OK')
 finally:v.close()
 assert hashlib.sha256(disk.read_bytes()).digest()==before
 print('OK: HDD final arranca sin ISO; NASM, framebuffer, FAT32 y TTF funcionan; HDD intacto.')
