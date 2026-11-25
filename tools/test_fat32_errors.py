import tempfile,struct,shutil,hashlib,os
from pathlib import Path
from test_external import fat_image
from vm_harness import VM,ROOT
with tempfile.TemporaryDirectory() as t:
 p=Path(t);fat,_=fat_image(p,False);raw=fat.read_bytes()
 cases={}
 bad=bytearray(raw);struct.pack_into('<H',bad,11,4096);cases['sector-4k']=(bad,'mount hdb /mnt/mal','Error:')
 bad=bytearray(raw);struct.pack_into('<I',bad,32,0xffffffff);cases['bpb-size']=(bad,'mount hdb /mnt/mal','Error:')
 bad=bytearray(raw);struct.pack_into('<I',bad,44,0);cases['root-zero']=(bad,'mount hdb /mnt/mal','Error:')
 reserved=struct.unpack_from('<H',raw,14)[0];size=struct.unpack_from('<I',raw,36)[0];nfat=raw[16];data=(reserved+nfat*size)*512
 directory=raw[data:data+512];entry=directory.find(b'TEST    BIN');assert entry>=0
 cluster=(struct.unpack_from('<H',directory,entry+20)[0]<<16)|struct.unpack_from('<H',directory,entry+26)[0]
 bad=bytearray(raw)
 for n in range(nfat):struct.pack_into('<I',bad,(reserved+n*size)*512+cluster*4,cluster)
 cases['fat-cycle']=(bad,'cat /mnt/mal/TEST.BIN','bucle en cadena')
 for name,(image,command,expect) in cases.items():
  folder=p/name;folder.mkdir();disk=folder/'disk.img';disk.write_bytes(image);before=hashlib.sha256(image).digest()
  v=VM(folder,disk_positions={1:disk})
  try:
   if name=='fat-cycle':v.cmd('mount hdb /mnt/mal','Montado')
   v.cmd(command,expect)
   v.cmd('memtest','Memoria: OK')
  finally:v.close()
  assert hashlib.sha256(disk.read_bytes()).digest()==before
  print('OK: FAT32',name,'rechazado/sin bloqueo y disco intacto.',flush=True)
print('FAT32 negative suite passed.')
