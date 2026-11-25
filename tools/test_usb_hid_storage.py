"""Keyboard interrupt reports and mass-storage bulk transfers share EHCI."""
import os,tempfile
from pathlib import Path
from test_external import fat_image
from vm_harness import VM
with tempfile.TemporaryDirectory() as tmp:
 p=Path(tmp);fat,_=fat_image(p,False)
 old=os.environ.get('QEMU_EXTRA_ARGS','')
 os.environ['QEMU_EXTRA_ARGS']=old+f' -device usb-ehci,id=ehci -drive file={fat},format=raw,if=none,id=d0 -device usb-storage,drive=d0,bus=ehci.0,port=2,id=u0'
 v=VM(p,memory=200)
 try:
  start=len(v.out());v.type('castctl usbscan');v.key('ret')
  v.qmp('device_add',{'driver':'usb-kbd','bus':'ehci.0','port':'1','id':'hid0','usb_version':2})
  scan=v.wait('asm:/ > ',start)
  assert '1 disco(s)' in scan and '1 teclado(s)' in scan,scan
  v.cmd('mount usb0 /mnt/usb','Montado')
  v.cmd('cat /mnt/usb/HELLO.TXT','FAT32 externo')
  v.cmd('echo hid-y-disco','hid-y-disco')
 finally:v.close();os.environ['QEMU_EXTRA_ARGS']=old
print('EHCI: teclado HID y disco FAT32 simultáneos OK.')
