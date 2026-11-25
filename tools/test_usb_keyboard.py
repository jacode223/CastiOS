"""Hotplug a high-speed boot keyboard and type through USB HID EHCI."""
import os,tempfile,time
from pathlib import Path
from vm_harness import VM
old=os.environ.get('QEMU_EXTRA_ARGS','')
os.environ['QEMU_EXTRA_ARGS']=old+' -device usb-ehci,id=ehci'
with tempfile.TemporaryDirectory() as tmp:
 v=VM(Path(tmp),memory=200)
 try:
  start=len(v.out());v.type('castctl usbscan');v.key('ret')
  v.qmp('device_add',{'driver':'usb-kbd','bus':'ehci.0','port':'1','id':'hid0','usb_version':2})
  scan=v.wait('asm:/ > ',start)
  assert '1 teclado(s)' in scan and 'lectura periodica activa' in scan,scan
  typed=v.cmd('echo hid-ok','hid-ok')
  assert typed.count('hid-ok')>=2,typed
  v.cmd('castctl usbkbd','entrada activa')
  v.qmp('device_del',{'id':'hid0'})
  time.sleep(.3)
  v.cmd('echo ps2-back','ps2-back')
  v.cmd('castctl usbscan','0 teclado(s)')
 finally:v.close();os.environ['QEMU_EXTRA_ARGS']=old
print('USB HID: teclado boot EHCI escribe en shell, informes periodicos activos.')
