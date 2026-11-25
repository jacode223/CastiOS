"""QEMU fault injection and unsupported-controller diagnostics."""
import hashlib, os, tempfile
from pathlib import Path
from fs_format import fresh, SIZE
from vm_harness import VM

def disk(path):
    fs=fresh()
    with path.open('wb') as f:
        f.truncate(32*1024*1024)
        f.seek(0);f.write(fs);f.seek(8192*512);f.write(fs)

with tempfile.TemporaryDirectory() as temp:
    p=Path(temp)
    raw=p/'errors.img';disk(raw)
    original=hashlib.sha256(raw.read_bytes()).digest()
    cfg=p/'blkdebug.conf'
    cfg.write_text('[inject-error]\nevent = "read_aio"\nerrno = "5"\nstate = "1"\nonce = "off"\nimmediately = "on"\n')
    old=os.environ.get('QEMU_EXTRA_ARGS','')
    os.environ['QEMU_EXTRA_ARGS']=old+f' -drive file=blkdebug:{cfg}:{raw},format=raw,if=none,id=err -device ide-hd,drive=err,bus=ide.0,unit=0'
    try:
        v=VM(p,disk_positions={})
        try:
            text=v.cmd('castctl disks')
            assert 'ATA LBA28' in text
            assert 'RMFS disponible en /ram' in v.out()
            assert 'fallos E/S: 0' not in text
            v.cmd('castctl write ram.txt conservado')
            v.cmd('cat ram.txt','conservado')
        finally:v.close()
    finally:os.environ['QEMU_EXTRA_ARGS']=old
    assert hashlib.sha256(raw.read_bytes()).digest()==original
    print('OK: errores de lectura reales: retorno a shell, RAM, contador, disco intacto',flush=True)

    os.environ['QEMU_EXTRA_ARGS']=old+' -machine q35'
    try:
        v=VM(p)
        try:
            v.cmd('castctl disks','SATA/AHCI')
            assert 'RMFS disponible en /ram' in v.out()
        finally:v.close()
    finally:os.environ['QEMU_EXTRA_ARGS']=old
    print('OK: AHCI sin disco: inventario PCI y arranque RAM',flush=True)

    nv=p/'nvme.img';disk(nv)
    os.environ['QEMU_EXTRA_ARGS']=old+f' -drive file={nv},format=raw,if=none,id=nv -device nvme,drive=nv,serial=ASMTEST'
    try:
        v=VM(p)
        try:
            v.cmd('castctl disks','NVMe (sin driver)')
            assert 'RMFS disponible en /ram' in v.out()
        finally:v.close()
    finally:os.environ['QEMU_EXTRA_ARGS']=old
    print('OK: NVMe detectado por PCI y limitacion explicada',flush=True)
print('ATA errors suite passed.')
