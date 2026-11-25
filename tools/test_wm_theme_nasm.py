"""Compile a palette inside CastiOS, reject invalid data and inspect framebuffer."""
import tempfile,time
from pathlib import Path
from fs_format import fresh,put,seal,SIZE
from vm_harness import VM
with tempfile.TemporaryDirectory() as tmp:
 p=Path(tmp); disk=p/'disk.img'; fs=fresh()
 source=b"bits 32\ndb 'CTH1'\ndd 0x0b1628,0x172f47,0x102539,0x297eb0,0x24536d,0xff0000,0x52677b,0xe5ebf2,0x12283d,0x286282,0xb5424c\n"
 put(fs,60,'theme.asm',source);put(fs,61,'bad.bin',b'BAD!')
 seal(fs);raw=bytearray(32*1024*1024);raw[:SIZE]=fs;raw[8192*512:8192*512+SIZE]=fs;disk.write_bytes(raw)
 v=VM(p,disk,memory=256)
 try:
  v.cmd('nasm -f bin theme.asm -o theme.bin','NASM terminado: OK')
  v.cmd('castctl wmtheme theme.bin','Tema cargado')
  v.cmd('castctl wmtheme bad.bin','tema invalido')
  v.type('desktop');v.key('ret');v.key('down');v.key('ret');time.sleep(.4)
  v.qmp('human-monitor-command',{'command-line':f'screendump {p/"screen.ppm"}'})
  pixels=(p/'screen.ppm').read_bytes().split(b'\n',3)[3]
  assert pixels[(210*1024+700)*3:(210*1024+700)*3+3]==bytes.fromhex('ff0000')
 finally:v.close()
print('OK: NASM in guest, palette loading, invalid data rejected, framebuffer color checked.')
