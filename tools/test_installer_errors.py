"""No-disk, undersized disk and actual write/readback failures in QEMU."""
import os,tempfile,hashlib
from pathlib import Path
from vm_harness import VM
old=os.environ.get('QEMU_EXTRA_ARGS','')
with tempfile.TemporaryDirectory() as tmp:
 p=Path(tmp)
 vm=VM(p,memory=32)
 try:
  off=len(vm.out());vm.type('install');vm.key('ret');vm.wait('SETUP WELCOME',off)
  vm.key('ret');vm.wait('SETUP DISKS',off);vm.key('ret');vm.key('esc')
  vm.wait('Instalacion cancelada',off);vm.wait('asm:/ > ',off)
 finally:vm.close()
 small=p/'small.img';small.write_bytes(bytes(1024*1024))
 vm=VM(p,small,memory=32)
 try:vm.cmd('install hda','Instalacion rechazada')
 finally:vm.close()
 assert small.read_bytes()==bytes(1024*1024)
 for mode in ('write','verify'):
  disk=p/(mode+'.img')
  with disk.open('wb') as f:f.truncate(48*1024*1024)
  cfg=p/'error.conf'
  cfg.write_text('[inject-error]\nevent = "write_aio"\nerrno = "5"\nstate = "1"\nonce = "off"\nimmediately = "on"\n' if mode=='write' else
   '[set-state]\nevent = "write_aio"\nstate = "1"\nnew_state = "2"\n\n[inject-error]\nevent = "read_aio"\nerrno = "5"\nstate = "2"\nonce = "off"\nimmediately = "on"\n')
  os.environ['QEMU_EXTRA_ARGS']=old+f' -drive file=blkdebug:{cfg}:{disk},format=raw,if=none,id=err -device ide-hd,drive=err,bus=ide.0,unit=0'
  try:
   vm=VM(p,disk_positions={},memory=32)
   try:
    off=len(vm.out());vm.type('install hda');vm.key('ret')
    vm.wait('Error ATA durante instalacion',off)
    vm.wait('asm:/ > ',off)
    assert 'Formateado e instalado' not in vm.out()[off:]
    if mode=='verify':assert 'Verificando lectura del disco' in vm.out()[off:]
    vm.cmd('echo shell-viva','shell-viva')
   finally:vm.close()
  finally:os.environ['QEMU_EXTRA_ARGS']=old
print('OK: no disk, small disk, injected write/readback failure, shell survives')
