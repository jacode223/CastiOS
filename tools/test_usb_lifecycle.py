import tempfile,os,hashlib
from pathlib import Path
from test_external import fat_image
from vm_harness import VM
with tempfile.TemporaryDirectory() as t:
 p=Path(t);a=p/'a';b=p/'b';a.mkdir();b.mkdir()
 raw,_=fat_image(a,False);mbr,_=fat_image(b,True)
 before=[hashlib.sha256(x.read_bytes()).digest() for x in (raw,mbr)]
 old=os.environ.get('QEMU_EXTRA_ARGS','')
 os.environ['QEMU_EXTRA_ARGS']=old+f' -device usb-ehci,id=ehci -drive file={raw},format=raw,if=none,id=d0 -drive file={mbr},format=raw,if=none,id=d1 -device usb-storage,drive=d0,bus=ehci.0,port=1,id=u0 -device usb-storage,drive=d1,bus=ehci.0,port=2,id=u1'
 v=VM(p)
 try:
  print(v.cmd('castctl usbscan','2 disco(s)'),flush=True)
  v.cmd('mount usb0 /mnt/a','Montado')
  v.cmd('mount usb1p1 /mnt/b','Montado')
  v.cmd('cat /mnt/a/HELLO.TXT','FAT32 externo')
  v.cmd('cat /mnt/b/HELLO.TXT','FAT32 externo')
  v.cmd('castctl usbscan','2 disco(s)')
  v.cmd('cat /mnt/a/HELLO.TXT','no montado')
  v.cmd('mount usb0 /mnt/a','Montado')
  v.qmp('device_del',{'id':'u0'})
  import time;time.sleep(.3)
  status=v.cmd('castctl usbinfo','desconectado/error')
  assert 'usb1' in status and 'fallos=0' in status,status
  failed=v.cmd('cat /mnt/a/HELLO.TXT')
  assert 'FAT32 externo' not in failed,failed
  v.cmd('castctl usbscan','1 disco(s)')
  v.cmd('mount usb0p1 /mnt/restante','Montado')
  v.cmd('cat /mnt/restante/HELLO.TXT','FAT32 externo')
  v.qmp('blockdev-add',{'driver':'file','filename':str(raw),'node-name':'usb-file-new'})
  v.qmp('blockdev-add',{'driver':'raw','file':'usb-file-new','node-name':'usb-disk-new'})
  v.qmp('device_add',{'driver':'usb-storage','drive':'usb-disk-new','bus':'ehci.0','port':'1','id':'u0new'})
  time.sleep(.3)
  v.cmd('castctl usbscan','2 disco(s)')
  v.cmd('mount usb0 /mnt/regreso','Montado')
  v.cmd('cat /mnt/regreso/HELLO.TXT','FAT32 externo')
  v.cmd('castctl memtest','Memoria: OK')
 finally:v.close();os.environ['QEMU_EXTRA_ARGS']=old
 assert [hashlib.sha256(x.read_bytes()).digest() for x in (raw,mbr)]==before
 print('OK: dos USB, direcciones distintas, superfloppy/MBR, rescan invalida montajes y retirada conserva el segundo.')
 with tempfile.TemporaryDirectory() as other:
  v=VM(Path(other))
  try:v.cmd('castctl usbscan','no hay EHCI')
  finally:v.close()
 print('OK: ausencia de EHCI explicada sin bloqueo.')
