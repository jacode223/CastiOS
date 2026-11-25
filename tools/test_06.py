import tempfile,shutil,subprocess,struct
from pathlib import Path
from vm_harness import VM,ROOT
checks=[]
def ok(m):checks.append(m);print('OK:',m,flush=True)
with tempfile.TemporaryDirectory() as t:
 p=Path(t);d=p/'data.img';shutil.copyfile(ROOT/'build/asfs2.img',d)
 v=VM(p,d)
 try:
  v.cmd('mem','Paging activo');v.cmd('memtest','Memoria: OK')
  regs=v.qmp('human-monitor-command',{'command-line':'info registers'})
  assert int(regs.split('CR0=')[1].split()[0],16)&0x80000000
  v.cmd('mkdir prueba');v.cmd('write /prueba/n.txt Recuperacion');v.cmd('asm demo.asm demo.app');v.cmd('run demo.app','EAX=42')
 finally:v.close()
 ok('GRUB Multiboot, CR0.PG, paginas, doble free, carpetas y programas')
 b=bytearray(d.read_bytes());b[600]^=1;d.write_bytes(b)
 v=VM(p,d)
 try:v.cmd('cat /prueba/n.txt','Recuperacion');assert 'copia recuperada' in v.out()
 finally:v.close()
 ok('Recuperacion de copia valida al corromper volumen primario')
 target=p/'target.img';target.write_bytes(bytes(32*1024*1024))
 v=VM(p,target)
 try:
  start=len(v.out());v.type('install hda');v.key('ret');v.wait('FORMAT hda',start);v.type('FORMAT hda');v.key('ret');v.wait('Formateado e instalado',start);v.wait('asm:/ > ',start)
  v.cmd('write grub.txt DiscoGRUB','Guardado en disco')
 finally:v.close()
 v=VM(p,target,boot_disk=True)
 try:v.cmd('cat grub.txt','DiscoGRUB');v.cmd('memtest','Memoria: OK')
 finally:v.close()
 ok('Instalador Live escribe GRUB y disco arranca sin ISO')
 host=p/'host.img';subprocess.run(['python3','tools/install_disk.py',str(host)],cwd=ROOT,check=True)
 v=VM(p,host,boot_disk=True)
 try:v.cmd('cat readme.txt','CastiOS');v.cmd('memtest','Memoria: OK')
 finally:v.close()
 ok('Disco GRUB generado por instalador host')
(ROOT/'docs/VALIDACION_0.6.txt').write_text('\n'.join(checks)+'\n')
