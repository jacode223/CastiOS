"""EHCI boot HID mouse movement and coexistence with a keyboard."""
import os,tempfile,time,re
from pathlib import Path
from vm_harness import VM
old=os.environ.get('QEMU_EXTRA_ARGS','')
os.environ['QEMU_EXTRA_ARGS']=old+' -device usb-ehci,id=ehci'
with tempfile.TemporaryDirectory() as tmp:
 v=VM(Path(tmp),memory=200)
 try:
  start=len(v.out());v.type('castctl usbscan');v.key('ret')
  v.qmp('device_add',{'driver':'usb-kbd','bus':'ehci.0','port':'1','id':'hid0','usb_version':2})
  v.qmp('device_add',{'driver':'usb-mouse','bus':'ehci.0','port':'2','id':'mouse0','usb_version':2})
  scan=v.wait('asm:/ > ',start)
  assert '1 teclado(s)' in scan and '1 raton(es)' in scan,scan
  v.cmd('echo teclado-ok','teclado-ok')
  devices=v.qmp('human-monitor-command',{'command-line':'info mice'}); assert any('*' in row and 'HID Mouse' in row for row in devices.splitlines()), devices
  initial=v.cmd('mousestat')
  v.qmp('human-monitor-command',{'command-line':'mouse_move -50 60'})
  time.sleep(.3)
  moved=v.cmd('mousestat')
  assert 'x=430 y=360' in moved,moved
  v.qmp('human-monitor-command',{'command-line':'mouse_button 1'});time.sleep(.2)
  clicked=v.cmd('mousestat');assert 'botones=1' in clicked,clicked
  v.qmp('human-monitor-command',{'command-line':'mouse_button 0'});time.sleep(.2)
  v.cmd('echo ambos-ok','ambos-ok')
  v.qmp('device_del',{'id':'mouse0'});time.sleep(.4)
  v.cmd('echo teclado-sigue','teclado-sigue')
  v.qmp('device_del',{'id':'hid0'});time.sleep(.4)
  v.cmd('echo ps2-sigue','ps2-sigue')
 finally:v.close();os.environ['QEMU_EXTRA_ARGS']=old
print('USB HID EHCI: teclado y raton simultaneos OK')
