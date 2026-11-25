"""Independent mkfs.fat/mtools images: FAT32, TTF, imports and USB EHCI."""
import os,struct,tempfile,subprocess,shutil,hashlib,uuid,zlib
from pathlib import Path
from vm_harness import VM,ROOT
from fs_format import validate,body,RECORD
from PIL import Image
def run(*args):subprocess.run(list(map(str,args)),check=True,stdout=subprocess.DEVNULL)
def fat_image(p,partition=True):
 raw=p/'fat.img'
 with raw.open('wb') as f:f.truncate(64*1024*1024)
 run(os.environ.get('MKFS_FAT','mkfs.fat'),'-F','32',raw)
 (p/'HELLO.TXT').write_text('FAT32 externo funciona\n')
 (p/'Long example.txt').write_text('Nombre largo correcto\n')
 pattern=bytes(range(256))*151
 (p/'TEST.BIN').write_bytes(pattern)
 (p/'BAD.TTF').write_bytes(b'\0\1\0\0'*4)
 font=Path(os.environ.get('TEST_TTF','/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf'))
 for name in ['HELLO.TXT','Long example.txt','TEST.BIN','BAD.TTF']:run('mcopy','-i',raw,p/name,'::/')
 run('mcopy','-i',raw,font,'::/MONO.TTF')
 run('mmd','-i',raw,'::/SUBDIR');run('mcopy','-i',raw,p/'HELLO.TXT','::/SUBDIR/INSIDE.TXT')
 if not partition:return raw,pattern
 if os.environ.get('EXT_MODE')=='gpt':
  disk=p/'gpt.img';size=raw.stat().st_size//512;count=size+2048+34;last=count-1
  mbr=bytearray(512);mbr[450]=0xee;struct.pack_into('<II',mbr,454,1,count-1);mbr[510:]=b'\x55\xaa'
  entries=bytearray(128*128);entries[:16]=uuid.UUID('ebd0a0a2-b9e5-4433-87c0-68b6b72699c7').bytes_le
  entries[16:32]=uuid.UUID('48ba1876-16a3-4d5f-bc60-63970ee44e00').bytes_le
  struct.pack_into('<QQQ',entries,32,2048,2048+size-1,0);entries[56:64]='DATA'.encode('utf-16le')
  def header(cur,backup,table):
   b=bytearray(512);struct.pack_into('<8sIIIIQQQQ16sQIII',b,0,b'EFI PART',0x10000,92,0,0,cur,backup,34,last-33,
    uuid.UUID('28b54b20-b272-4759-b1e9-77ab017bd176').bytes_le,table,128,128,zlib.crc32(entries))
   struct.pack_into('<I',b,16,zlib.crc32(b[:92]));return b
  with disk.open('wb') as f:
   f.truncate(count*512);f.write(mbr);f.write(header(1,last,2));f.write(entries);f.seek(2048*512)
   with raw.open('rb') as data:shutil.copyfileobj(data,f)
   f.seek((last-32)*512);f.write(entries);f.write(header(last,1,last-32))
  return disk,pattern
 disk=p/'mbr.img';mbr=bytearray(512);mbr[446+4]=0x0c;struct.pack_into('<II',mbr,454,2048,raw.stat().st_size//512);mbr[510:]=b'\x55\xaa'
 with disk.open('wb') as f:
  f.truncate(raw.stat().st_size+2048*512);f.seek(0);f.write(mbr);f.seek(2048*512)
  with raw.open('rb') as data:shutil.copyfileobj(data,f)
 return disk,pattern
def getfont(v,path):
 blob=(ROOT/'src/console/font8x16.bin').read_bytes();offset=(ROOT/'build/kernel.bin').read_bytes().find(blob);assert offset>=0
 v.qmp('human-monitor-command',{'command-line':f'pmemsave {offset+0x10000} 4096 "{path}"'})
 return path.read_bytes()
if __name__ == "__main__":
 mode=os.environ.get('EXT_MODE','ide')
 with tempfile.TemporaryDirectory() as t:
  p=Path(t);fat,pattern=fat_image(p,partition=mode!='usb');before=hashlib.sha256(fat.read_bytes()).digest()
  data=p/'asfs.img';shutil.copyfile(ROOT/'build/asfs4.img',data)
  old=os.environ.get('QEMU_EXTRA_ARGS','')
  kwargs={'slave':fat}
  if mode=='usb':
   os.environ['QEMU_EXTRA_ARGS']=old+f' -device usb-ehci,id=ehci -drive file={fat},format=raw,if=none,id=stickdata -device usb-storage,drive=stickdata,bus=ehci.0,port=1,id=stick'
   kwargs={}
  elif mode=='ahci':
   os.environ['QEMU_EXTRA_ARGS']=old+f' -device ich9-ahci,id=sata -drive file={fat},format=raw,if=none,id=fatdata -device ide-hd,drive=fatdata,bus=sata.2'
   kwargs={}
  v=VM(p,data,**kwargs)
  try:
   v.cmd('console','framebuffer')
   if mode=='usb':
    print(v.cmd('usbscan'),flush=True)
    v.cmd('usbinfo','usb0')
    v.cmd('mount usb0 /mnt/datos','Montado FAT32')
   else:
    print(v.cmd('volumes'),flush=True)
    v.cmd('mount hdb1 /mnt/datos','Montado FAT32')
   v.cmd('ls /mnt/datos','HELLO.TXT')
   v.cmd('cat /mnt/datos/Long example.txt','Nombre largo correcto')
   v.cmd('cd /mnt/datos');v.cmd('pwd','/mnt/datos')
   v.cmd('cat hello.txt','FAT32 externo funciona')
   v.cmd('cd subdir');v.cmd('cat inside.txt','FAT32 externo funciona');v.cmd('cd ..')
   v.cmd('write no.txt prohibido','solo lectura')
   v.cmd('cp /mnt/datos/TEST.BIN /import.bin','Importado a ASFS')
   orig=getfont(v,p/'original.bin')
   print(v.cmd('font /mnt/datos/MONO.TTF','TTF aplicada'),flush=True)
   changed=getfont(v,p/'changed.bin');assert changed!=orig
   capture=ROOT/'build'/f'external-{mode}.ppm';v.qmp('screendump',{'filename':str(capture)})
   Image.open(capture).save(ROOT/'build'/f'external-{mode}.png')
   v.cmd('font /mnt/datos/BAD.TTF','TTF invalida')
   assert getfont(v,p/'still.bin')==changed
   v.cmd('font default','restaurada');assert getfont(v,p/'reset.bin')==orig
   v.cmd('cp /mnt/datos/MONO.TTF /mono.ttf','Importado a ASFS')
   v.cmd('font /mono.ttf','TTF aplicada')
   assert getfont(v,p/'from-asfs.bin')==changed
   v.cmd('font default','restaurada')
   if mode=='usb':
    v.qmp('device_del',{'id':'stick'})
    import time;time.sleep(.3)
    print(v.cmd('cat /mnt/datos/HELLO.TXT','Error:'),flush=True)
   v.cmd('cd /');v.cmd('umount /mnt/datos','desmontado')
   v.cmd('mount')
   v.cmd('memtest','Memoria: OK')
  finally:v.close();os.environ['QEMU_EXTRA_ARGS']=old
  assert hashlib.sha256(fat.read_bytes()).digest()==before
  fs=validate(data.read_bytes());i=next(i for i in range(256) if fs[512+i*RECORD:512+i*RECORD+32].split(b'\0')[0]==b'import.bin')
  assert body(fs,i)==pattern
  print('OK:',mode,'FAT32, LFN, rutas, TTF real, error atomico, importacion exacta y volumen externo intacto.',flush=True)
