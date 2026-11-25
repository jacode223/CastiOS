"""Pruebas de la version 0.5, siempre sobre copias de discos temporales."""
from pathlib import Path
import os
import re
import shutil
import struct
import subprocess
import tempfile
from vm_harness import VM, ROOT
from fs_format import validate, extract_or_migrate, SIZE, RECORD, HEADER, ROOT as ROOT_ID, seal, blank, put

checks=[]
def ok(message):checks.append(message);print('OK:',message,flush=True)

def install(vm,target,confirm):
    start=len(vm.out());vm.type('install '+target);vm.key('ret')
    vm.wait('FORMAT '+target,start)
    vm.type(confirm);vm.key('ret')
    return vm.wait('asm:/ > ',start)

def nano(vm,name,text=None,keys=(),save=True):
    start=len(vm.out());vm.type('nano '+name);vm.key('ret');vm.wait('ASM nano | ',start)
    if text is not None:vm.type(text)
    for key in keys:
        if isinstance(key,tuple):vm.type(key[0])
        else:vm.key(key)
    if save:vm.key('ctrl-o')
    start=len(vm.out());vm.key('ctrl-x')
    vm.wait('asm:/ > ',start)

with tempfile.TemporaryDirectory(prefix='asm05-tests-') as directory:
    work=Path(directory);disk=work/'data.img';shutil.copyfile(ROOT/'build/asfs2.img',disk)
    vm=VM(work,disk,serial=True)
    try:
        assert 'ASFS v2: disco persistente' in vm.out()
        vm.cmd('drivers','ps2 ready input');vm.cmd('drvtest','Driver API tests: OK')
        vm.cmd('drvwrite serial Driver05','8 bytes escritos')
        assert 'Driver05' in (work/'serial.log').read_text()
        vm.cmd('disks','8192 sectores');vm.cmd('kbdstat','0 scancodes descartados')
        assert re.search(r'\n\d{2}:\d{2}:\d{2}\n',vm.cmd('time'))
        vm.cmd('uptime','segundos')
        ok('Drivers IRQ1/PIT/ATA/serial, capacidad IDE y cola sin perdidas')
        vm.cmd('mkdir trabajo','Guardado en disco');vm.cmd('mkdir /trabajo/sub','Guardado en disco')
        vm.cmd('cd /trabajo/sub');vm.cmd('pwd','/trabajo/sub/')
        vm.cmd('write nota.txt Dentro','Guardado en disco');vm.cmd('cat ./nota.txt','Dentro')
        vm.cmd('cd ..');vm.cmd('pwd','/trabajo/');vm.cmd('write nota.txt Padre')
        vm.cmd('cat /trabajo/sub/nota.txt','Dentro');vm.cmd('cat nota.txt','Padre')
        vm.cmd('rm sub','Ruta o tipo invalido');vm.cmd('rm .','Ruta o tipo invalido')
        vm.cmd('write '+('x'*32)+' dato','Ruta o tipo invalido')
        vm.cmd('cd /');vm.cmd('pwd','\n/\n')
        ok('Carpetas anidadas, rutas / . .., nombres por padre y rechazo de borrado no vacio')
        nano(vm,'/trabajo/sub/editor.txt','abc\nxyz',keys=['home','right',('Q',),'up',('Z',)])
        vm.cmd('cat /trabajo/sub/editor.txt','abZc\nxQyz')
        # Salir sin guardar conserva el archivo anterior.
        start=len(vm.out());vm.type('nano /trabajo/sub/editor.txt');vm.key('ret');vm.wait('ASM nano | ',start)
        vm.type('Descartar');vm.key('ctrl-x');vm.wait('Guardar cambios?',start)
        vm.key('n');vm.wait('asm:/ > ',start)
        vm.cmd('cat /trabajo/sub/editor.txt','abZc\nxQyz')
        vm.cmd('touch vacio');nano(vm,'vacio','',save=True)
        nano(vm,'teclas.txt','abc',keys=['left','backspace',('X',),'delete',('Y',)])
        vm.cmd('cat teclas.txt','aXY')
        if os.environ.get('CASTIOS_SCREENSHOT'):
            start=len(vm.out());vm.type('nano /trabajo/sub/editor.txt');vm.key('ret');vm.wait('ASM nano | ',start)
            vm.qmp('screendump',{'filename':os.environ['CASTIOS_SCREENSHOT']})
            vm.key('ctrl-x');vm.wait('asm:/ > ',start)
        ok('Nano pantalla completa: crear, multilinea, flechas, Home, Supr, guardar y descartar')
        vm.cmd('asm demo.asm demo.app','Ensamblado AX05 listo')
        vm.cmd('run demo.app','EAX=42')
        vm.cmd('write calculo.asm mov eax, 0x20')
        vm.cmd('append calculo.asm add eax, 12');vm.cmd('append calculo.asm dec eax');vm.cmd('append calculo.asm ret')
        vm.cmd('asm calculo.asm calculo.app','Ensamblado AX05 listo');vm.cmd('run calculo.app','EAX=43')
        vm.cmd('write error.asm cli');vm.cmd('append error.asm ret')
        vm.cmd('asm error.asm demo.app','Error de ensamblado')
        vm.cmd('run demo.app','EAX=42')
        vm.cmd('run demo.asm','Binario no valido')
        ok('Ensamblador nativo x86 y ejecucion; sintaxis incorrecta no destruye salida')
        # La entrada de 250 caracteres se recorta sin corromper el siguiente buffer.
        vm.cmd('echo '+'x'*260,'x'*245)
        vm.cmd('cat readme.txt','CastiOS 0.8')
        start=len(vm.out());vm.type('reboot');vm.key('ret');vm.wait('CastiOS 0.8',start);vm.wait('asm:/ > ',start)
        vm.cmd('cat /trabajo/sub/editor.txt','abZc\nxQyz');vm.cmd('run demo.app','EAX=42')
    finally:vm.close()
    data=disk.read_bytes();validate(data)
    vm=VM(work,disk)
    try:vm.cmd('cat /trabajo/sub/nota.txt','Dentro')
    finally:vm.close()
    ok('Persistencia de carpetas, texto y binarios tras reinicio y cierre completo')
    # Dos discos. Formatear solo hdb, incluso si contiene datos ajenos.
    slave=work/'slave.img';slave.write_bytes(b'OTRO SISTEMA'+bytes(4*1024*1024-12))
    before_master=disk.read_bytes();before_slave=slave.read_bytes()
    vm=VM(work,disk,slave=slave)
    try:
        vm.cmd('install desconocido','Uso: install hda')
        assert 'Instalacion cancelada' in install(vm,'hdb','NO')
        assert slave.read_bytes()==before_slave
        assert 'Formateado e instalado' in install(vm,'hdb','FORMAT hdb')
        vm.cmd('mkdir nuevo');vm.cmd('write /nuevo/arranque.txt HDB independiente','Guardado en disco')
        vm.cmd('asm /demo.asm prog.app','El archivo no existe')
    finally:vm.close()
    assert disk.read_bytes()==before_master
    assert slave.read_bytes()[0x188]==1
    validate(slave.read_bytes()[65536:])
    vm=VM(work,disk,boot_disk=True,slave=slave,boot_slave=True)
    try:
        vm.cmd('cat /nuevo/arranque.txt','HDB independiente')
        vm.cmd('write /nuevo/segundo.txt Persistente','Guardado en disco')
        vm.cmd('disks','hdb 8192 sectores')
    finally:vm.close()
    assert disk.read_bytes()==before_master
    ok('Instalador selecciona y formatea hdb con confirmacion; hda intacto; arranque sin ISO')
    # Migracion de ASFS1 desde copia de la imagen de la version 0.4.
    legacy=ROOT/'build/asfs.img'
    if legacy.exists():
        migrated=extract_or_migrate(legacy.read_bytes());validate(migrated)
        ok('Migracion ASFS1 a ASFS2 validada sin modificar el origen')
    host=work/'host.img'
    subprocess.run(['python3','tools/install_disk.py',str(host),'--data',str(disk)],cwd=ROOT,check=True)
    vm=VM(work,host,boot_disk=True)
    try:vm.cmd('cat /trabajo/sub/editor.txt','abZc\nxQyz');vm.cmd('run demo.app','EAX=42')
    finally:vm.close()
    ok('Instalador host importa ASFS2 con carpetas y ejecutables')
    # Un ciclo de carpetas con checksum correcto debe ser rechazado por el kernel.
    bad=bytearray(disk.read_bytes());struct.pack_into('<I',bad,512+2*RECORD+32,2)
    struct.pack_into('<I',bad,16,sum(bad[512:SIZE]));broken=work/'broken.img';broken.write_bytes(bad)
    vm=VM(work,broken)
    try:vm.cmd('write prueba RAM','solo en RAM')
    finally:vm.close()
    assert broken.read_bytes()==bad
    ok('Volumen corrupto con ciclo se rechaza sin escrituras')
    # Limites completos sin introducir miles de teclas artificialmente.
    fs=blank()
    for i in range(64):put(fs,i,'f'+str(i),b'contenido')
    put(fs,0,'lleno.txt',b'x'*4000)
    put(fs,1,'mal.app',b'AX05'+struct.pack('<I',2)+b'\xfa\xc3',kind=3)
    seal(fs);limited=work/'limited.img';limited.write_bytes(fs+bytes(4*1024*1024-len(fs)))
    vm=VM(work,limited)
    try:
        vm.cmd('write nuevo no','ASFS lleno')
        vm.cmd('append lleno.txt x','Limite de archivo')
        nano(vm,'lleno.txt','y',save=True)
        vm.cmd('run mal.app','Binario no valido')
        vm.cmd('rm f2','Guardado en disco')
        vm.cmd('write nuevo Libre','Guardado en disco')
    finally:vm.close()
    result=validate(limited.read_bytes())
    assert struct.unpack_from('<I',result,512+40)[0]==4000
    assert result[512+64:512+64+4000]==b'x'*4000
    ok('64 entradas, archivo de 4000 bytes, editor lleno y rechazo de codigo no permitido')
(ROOT/'docs/VALIDACION_0.5.txt').write_text('\n'.join('OK: '+m for m in checks)+'\n',encoding='utf8')
print('Version 0.5: pruebas superadas.')
