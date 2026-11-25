import tempfile,os,hashlib
from pathlib import Path
from vm_harness import VM
from fs_format import fresh,put,seal,validate,body,SIZE,RECORD
with tempfile.TemporaryDirectory() as t:
 p=Path(t);d=p/'sata.img'
 fs=fresh();put(fs,40,'sata.txt',b'AHCI real');seal(fs)
 raw=bytearray(32*1024*1024);raw[:SIZE]=fs;raw[8192*512:8192*512+SIZE]=fs;d.write_bytes(raw)
 old=os.environ.get('QEMU_EXTRA_ARGS','')
 controller=os.environ.get('AHCI_TEST_CONTROLLER',' -device ich9-ahci,id=sata')
 port=os.environ.get('AHCI_TEST_PORT','sata.0')
 os.environ['QEMU_EXTRA_ARGS']=old+controller+f' -drive file={d},format=raw,if=none,id=data -device ide-hd,drive=data,bus={port}' 
 for iteration in range(2):
  v=VM(p)
  try:
   print(v.cmd('disks'),flush=True)
   v.cmd('cat sata.txt','AHCI real')
   if not iteration:v.cmd('castctl write persist.txt SATA_guardado','Guardado en disco')
   else:v.cmd('cat persist.txt','SATA_guardado')
   v.cmd('castctl memtest','Memoria: OK')
  finally:v.close()
 data=d.read_bytes();fs=validate(data);assert data[:SIZE]==data[8192*512:8192*512+SIZE]
 i=next(i for i in range(256) if fs[512+i*RECORD:512+i*RECORD+32].split(b'\0')[0]==b'persist.txt')
 assert body(fs,i)==b'SATA_guardado'
 print('OK: AHCI IDENTIFY, lectura, escritura exacta, flush, espejo y reinicio.')
