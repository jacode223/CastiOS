import os,tempfile,hashlib
from pathlib import Path
from vm_harness import VM
from fs_format import fresh,SIZE
old=os.environ.get('QEMU_EXTRA_ARGS','')
for event in ('read_aio','write_aio'):
 with tempfile.TemporaryDirectory() as t:
  p=Path(t);d=p/'disk.img';cfg=p/'error.conf';fs=fresh()
  raw=bytearray(32*1024*1024);raw[:SIZE]=fs;raw[8192*512:8192*512+SIZE]=fs;d.write_bytes(raw)
  before=hashlib.sha256(raw).digest()
  cfg.write_text(f'[inject-error]\nevent = "{event}"\nerrno = "5"\nstate = "1"\nonce = "off"\nimmediately = "on"\n')
  os.environ['QEMU_EXTRA_ARGS']=old+f' -device ich9-ahci,id=sata -drive file=blkdebug:{cfg}:{d},format=raw,if=none,id=data -device ide-hd,drive=data,bus=sata.0'
  v=VM(p)
  try:
   if event=='read_aio':assert 'RMFS disponible en /ram' in v.out()
   else:v.cmd('castctl write fallo.txt error')
   text=v.cmd('disks');assert 'fallos E/S: 0' not in text
   v.cmd('castctl memtest','Memoria: OK')
  finally:v.close()
  assert hashlib.sha256(d.read_bytes()).digest()==before
  print('OK: AHCI',event,'error, disco intacto, shell y memoria operativas.',flush=True)
os.environ['QEMU_EXTRA_ARGS']=old
