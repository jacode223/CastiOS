"""Live installer on secondary slave; primary disk must remain unchanged."""
import hashlib,tempfile
from pathlib import Path
from vm_harness import VM
from fs_format import fresh,validate,extract_or_migrate

with tempfile.TemporaryDirectory() as tmp:
    p=Path(tmp);master=p/'master.img';target=p/'target.img'
    master.write_bytes(bytes(32*1024*1024));target.write_bytes(bytes(32*1024*1024))
    before=hashlib.sha256(master.read_bytes()).digest()
    v=VM(p,disk_positions={0:master,3:target})
    try:
        start=len(v.out());v.type('install hdd');v.key('ret');v.wait('FORMAT hdd',start)
        v.type('NO');v.key('ret');v.wait('Instalacion cancelada',start)
        assert target.read_bytes()==bytes(32*1024*1024)
        start=len(v.out());v.type('install hdd');v.key('ret');v.wait('FORMAT hdd',start)
        v.type('FORMAT hdd');v.key('ret');v.wait('Formateado e instalado',start);v.wait('asm:/ > ',start)
        v.cmd('write secundario.txt instalado','Guardado en disco')
    finally:v.close()
    assert hashlib.sha256(master.read_bytes()).digest()==before
    validate(extract_or_migrate(target.read_bytes()))
    # Only installed secondary disk; BIOS and GRUB boot without a CD.
    v=VM(p,boot_disk=True,disk_positions={3:target})
    try:
        v.cmd('cat secundario.txt','instalado')
        text=v.cmd('disks')
        assert '[activo]' in next(line for line in text.splitlines() if line.startswith('hdd '))
        v.cmd('nasm -v','NASM version 3.02')
    finally:v.close()
    assert hashlib.sha256(master.read_bytes()).digest()==before
print('OK: install hdd: cancelar, confirmar, conservar hda, ASFS valido, reinicio sin ISO y NASM.')
