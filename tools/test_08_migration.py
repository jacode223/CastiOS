"""Focused checks: ASFS3 migration, external import and live-installed NASM."""
import tempfile,os,struct,subprocess
from pathlib import Path
from fs_format import fresh,put,seal,validate,body,SIZE,RECORD
from vm_harness import VM,ROOT

with tempfile.TemporaryDirectory() as directory:
 p=Path(directory);d=p/'old.img'
 # Authentic ASFS3 layout: no extents, otherwise same record geometry.
 fs=fresh();fs[:4]=b'ASF3';struct.pack_into('<I',fs,4,3)
 raw=bytearray(32*1024*1024);raw[:SIZE]=fs;raw[8192*512:8192*512+SIZE]=fs;d.write_bytes(raw)
 before=d.read_bytes();v=VM(p,d)
 try:v.cmd('cat readme.txt','CastiOS 0.8');v.cmd('write migrated.txt preserved','Guardado en disco')
 finally:v.close()
 fs=validate(d.read_bytes());assert body(fs,0)==body(before,0)
 print('OK: kernel migra ASFS3 al guardar, conservando contenido',flush=True)
 # CLI imports big source and extracts the exact same bytes, leaves input alone.
 source=p/'source.asm';source.write_bytes(b'; imported\n'*2500+b'bits 32\nret\n')
 out=p/'new.img';export=p/'export.asm';before=d.read_bytes()
 subprocess.run(['python3','tools/asfs.py',str(d),'put',str(source),'/source.asm',str(out)],cwd=ROOT,check=True)
 subprocess.run(['python3','tools/asfs.py',str(out),'get','/source.asm',str(export)],cwd=ROOT,check=True)
 assert export.read_bytes()==source.read_bytes() and d.read_bytes()==before
 print('OK: importar/exportar fuente de mas de 27000 bytes sin modificar origen',flush=True)
 # Use the actual interactive formatter, then remove the ISO and test NASM.
 extra=os.environ.get('QEMU_EXTRA_ARGS','');os.environ['QEMU_EXTRA_ARGS']=extra+' -m 256'
 disk=p/'blank.img';disk.write_bytes(bytes(32*1024*1024));v=VM(p,disk)
 try:
  start=len(v.out());v.type('install hda');v.key('ret');v.wait('FORMAT hda',start)
  v.type('FORMAT hda');v.key('ret');v.wait('Formateado e instalado',start);v.wait('asm:/ > ',start)
  v.cmd('write installed.asm bits 32')
  v.cmd('append installed.asm mov eax, 77')
  v.cmd('append installed.asm ret')
 finally:v.close()
 v=VM(p,disk,boot_disk=True)
 try:v.cmd('nasm -f bin installed.asm -o installed.bin','NASM terminado: OK')
 finally:v.close()
 fs=validate(disk.read_bytes()[16*1024*1024:]);assert any(fs[512+i*RECORD:512+i*RECORD+14]==b'installed.bin\0' for i in range(256))
 print('OK: instalador Live incluye NASM; arranque sin CD y ensamblado persistente',flush=True)
 os.environ['QEMU_EXTRA_ARGS']=extra
