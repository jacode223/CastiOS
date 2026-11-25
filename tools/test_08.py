"""QEMU integration: real NASM, persistent extents and transaction rollback."""
import os,subprocess,tempfile,struct,hashlib
from pathlib import Path
from fs_format import fresh,put,seal,validate,body,extract_or_migrate,SIZE,RECORD
from vm_harness import VM,ROOT

checks=[]
def ok(text):checks.append(text);print('OK:',text,flush=True)
def index(fs,name):
 return next(i for i in range(256) if fs[512+i*RECORD:512+i*RECORD+32].split(b'\0')[0]==name.encode())
def image(path,fs):
 seal(fs);raw=bytearray(32*1024*1024);raw[:SIZE]=fs;raw[8192*512:8192*512+SIZE]=fs;path.write_bytes(raw)
def digest(path):return hashlib.sha256(path.read_bytes()).digest()

with tempfile.TemporaryDirectory() as directory:
 p=Path(directory);d=p/'data.img';fs=fresh()
 put(fs,5,'inc',kind=2)
 put(fs,6,'defs.inc',b'%define VALUE 65\n',parent=5)
 put(fs,7,'macro.asm',b'bits 32\n%include "/inc/defs.inc"\n%macro EMIT 1\ntimes %1 db VALUE\n%endmacro\nstart:\nEMIT 30000\n')
 put(fs,8,'broken.asm',b'bits 32\nthis is invalid nasm syntax\n')
 put(fs,9,'huge.asm',b'times 2100000 db 0\n')
 # Source itself spans several records; a marker after byte 16000 must parse.
 large=(b'; long comment\n'*2000)+b'bits 32\nmov eax, 123\nret\n'
 put(fs,10,'long.asm',large)
 image(d,fs)
 extra=os.environ.get('QEMU_EXTRA_ARGS','')
 os.environ['QEMU_EXTRA_ARGS']=extra+' -m 256'
 v=VM(p,d)
 try:
  v.cmd('nasm -v','NASM version 3.02')
  v.cmd('nasm -f bin app.asm -o app.ax','NASM terminado: OK')
  v.cmd('run app.ax','EAX=42')
  v.cmd('nasm -f bin macro.asm -o macro.bin','NASM terminado: OK')
  v.cmd('ls','macro.bin 30000')
  v.cmd('nasm -f bin long.asm -o long.bin','NASM terminado: OK')
  v.cmd('nasm -f elf32 demo.asm -o demo.o','NASM terminado: OK')
  ok('NASM 3.02 dentro de QEMU: macros, include, etiquetas, fuente grande, ELF32 y app AX05 ejecutada')
  # Stop the VM before reading host bytes; no concurrent image inspection.
 finally:v.close()
 fs=validate(d.read_bytes());assert body(fs,index(fs,'macro.bin'))==b'A'*30000
 assert body(fs,index(fs,'long.bin'))==b'\xb8\x7b\0\0\0\xc3'
 assert body(fs,index(fs,'demo.o'))[:4]==b'\x7fELF'
 assert d.read_bytes()[:SIZE]==d.read_bytes()[8192*512:8192*512+SIZE]
 ok('Binarios exactos de 30000 bytes y datos que cruzan extents; ambas copias coherentes')
 before=digest(d)
 v=VM(p,d)
 try:
  v.cmd('nasm -f bin broken.asm -o macro.bin','transaccion descartada')
  v.cmd('nasm -f bin absent.asm -o macro.bin','transaccion descartada')
  v.cmd('nasm -f bin demo.asm -o docs','transaccion descartada')
  v.cmd('nasm -f bin huge.asm -o huge.bin','transaccion descartada')
 finally:v.close()
 assert digest(d)==before
 ok('Errores de sintaxis, fuente ausente, destino carpeta y falta de espacio: disco intacto')
 v=VM(p,d)
 try:
  v.cmd('mkdir out')
  v.type('cd out');v.key('ret');v.wait('asm:/ > ')
  v.cmd('nasm -f bin ../demo.asm -o small.bin','NASM terminado: OK')
  v.cmd('cd /')
  v.cmd('nasm -f bin demo.asm -o macro.bin','NASM terminado: OK')
  v.cmd('rm long.asm')
  v.cmd('memtest','Memoria: OK')
 finally:v.close()
 fs=validate(d.read_bytes());assert body(fs,index(fs,'macro.bin'))==b'\xb8\x28\0\0\0\x83\xc0\x02\xc3'
 assert not any(fs[512+i*RECORD:512+i*RECORD+9]==b'long.asm\0' for i in range(256))
 ok('Rutas relativas, carpeta de salida, truncado y liberacion de extents, asignador de memoria')
 # Mirror recovery even with destroyed primary magic, both in host and kernel.
 raw=bytearray(d.read_bytes());raw[:4]=b'FAIL';d.write_bytes(raw)
 validate(extract_or_migrate(raw))
 v=VM(p,d)
 try:
  assert 'copia recuperada' in v.out();v.cmd('cat /docs/nota.txt','ASFS4')
 finally:v.close()
 ok('Recuperacion desde copia secundaria aunque la firma primaria este destruida')
 # Invalid chain with a correct checksum must never mount as persistent.
 bad=fresh();put(bad,20,'loop.bin',b'x'*9000,kind=3)
 nxt=struct.unpack_from('<I',bad,512+20*RECORD+44)[0]-1
 struct.pack_into('<I',bad,512+nxt*RECORD+44,nxt+1);seal(bad)
 try:validate(bad);raise AssertionError('host accepted loop')
 except ValueError:pass
 image(d,bad);v=VM(p,d)
 try:assert 'ASFS v4 en RAM' in v.out()
 finally:v.close()
 ok('Cadenas corruptas con checksum valido rechazadas por host y kernel')
 # Installed disk must include the assembler module too, without the CD-ROM.
 clean=p/'clean.img';image(clean,fresh());hdd=p/'boot.img'
 subprocess.run(['python3','tools/install_disk.py',str(hdd),'--data',str(clean)],cwd=ROOT,check=True)
 v=VM(p,hdd,boot_disk=True)
 try:v.cmd('nasm -f bin app.asm -o app.ax','NASM terminado: OK');v.cmd('run app.ax','EAX=42')
 finally:v.close()
 ok('NASM funciona desde disco instalado GRUB sin ISO')
 os.environ['QEMU_EXTRA_ARGS']=extra
 # Keep testing the low-memory base system and the interactive disk installer.
 subprocess.run(['python3','tools/test_08_regression.py'],cwd=ROOT,check=True)
 ok('Regresion: MiniDRV, nano, memoria, persistencia e instalador Live con GRUB')
 subprocess.run(['python3','tools/test_08_migration.py'],cwd=ROOT,check=True)
 ok('Migracion ASFS3 en kernel, importacion grande e instalador Live con NASM sin CD')

(ROOT/'docs/VALIDACION_0.8.txt').write_text('\n'.join(checks)+'\n')
