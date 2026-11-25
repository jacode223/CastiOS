import tempfile,shutil,hashlib
from pathlib import Path
from vm_harness import VM,ROOT
from test_external import fat_image
from fs_format import validate,body,RECORD
with tempfile.TemporaryDirectory() as t:
 p=Path(t);fat,_=fat_image(p,True);data=p/'asfs.img';shutil.copyfile(ROOT/'build/asfs4.img',data)
 before=hashlib.sha256(fat.read_bytes()).digest()
 v=VM(p,data,slave=fat)
 try:
  v.cmd('VER','CastiOS')
  v.cmd('mount hdb1 /mnt/datos','Montado')
  v.cmd('DIR /mnt/datos','HELLO.TXT')
  v.cmd('TYPE /mnt/datos/HELLO.TXT','FAT32 externo funciona')
  v.cmd('COPY /mnt/datos/HELLO.TXT /dos.txt','Importado a ASFS')
  v.cmd('TYPE /dos.txt','FAT32 externo funciona')
  v.cmd('CLS')
 finally:v.close()
 fs=validate(data.read_bytes())
 i=next(i for i in range(256) if fs[512+i*RECORD:512+i*RECORD+32].split(b'\0')[0]==b'dos.txt')
 assert body(fs,i)==b'FAT32 externo funciona\n'
 assert hashlib.sha256(fat.read_bytes()).digest()==before
print('OK: DIR/TYPE/COPY/CLS/VER mayusculas, FAT32 y copia exacta a ASFS.')
