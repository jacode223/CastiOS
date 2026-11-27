import os,tempfile,hashlib
from pathlib import Path
from vm_harness import VM
from fs_format import fresh,SIZE,validate,extract_or_migrate
with tempfile.TemporaryDirectory() as t:
 p=Path(t);ide=p/'ide.img';sata=p/'sata.img';fs=fresh()
 raw=bytearray(32*1024*1024);raw[:SIZE]=fs;raw[8192*512:8192*512+SIZE]=fs;ide.write_bytes(raw);sata.write_bytes(bytes(len(raw)))
 before=hashlib.sha256(ide.read_bytes()).digest()
 os.environ['QEMU_EXTRA_ARGS']=os.environ.get('QEMU_EXTRA_ARGS','')+f' -device ich9-ahci,id=sata -drive file={sata},format=raw,if=none,id=data -device ide-hd,drive=data,bus=sata.3,bootindex=7'
 v=VM(p,ide,memory=256)
 try:
  print(v.cmd('disks'),flush=True)
  start=len(v.out());v.type('install hdb');v.key('ret');v.wait('FORMAT hdb',start)
  v.type('FORMAT hdb');v.key('ret');v.wait('Formateado e instalado',start);v.wait('asm:/ > ',start)
  v.cmd('castctl write sata-boot.txt instalado','Guardado en disco')
 finally:v.close()
 assert hashlib.sha256(ide.read_bytes()).digest()==before
 validate(extract_or_migrate(sata.read_bytes()))
 v=VM(p,boot_disk=True,memory=256)
 try:
  v.cmd('cat sata-boot.txt','instalado')
  v.cmd('nasm -v','NASM version 3.02')
 finally:v.close()
 print('OK: IDE+AHCI, instalacion SATA, IDE intacto, arranque SATA sin CD, NASM.')
