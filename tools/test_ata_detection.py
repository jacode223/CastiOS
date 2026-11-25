"""Real QEMU tests: four IDE positions, fallback, integrity, large disks, 4Kn.
Run after build.sh; requires 256 MiB for the bundled assembler.
"""
import hashlib, os, shutil, subprocess, tempfile
from pathlib import Path
from fs_format import fresh, put, seal, validate, body, SIZE, RECORD
from vm_harness import VM, ROOT

def image(path, marker=b'ATA test'):
    fs=fresh()
    put(fs, 40, 'ata-marker.txt', marker)
    seal(fs)
    with path.open('wb') as f:
        f.truncate(32*1024*1024)
        f.seek(0); f.write(fs)
        f.seek(8192*512); f.write(fs)

def verify(path, filename, expected):
    with path.open('rb') as f:
        fs=validate(f.read(SIZE))
        f.seek(8192*512); assert f.read(SIZE)==fs
    idx=next(i for i in range(256) if fs[512+i*RECORD:512+i*RECORD+32].split(b'\0')[0]==filename.encode())
    assert body(fs,idx)==expected

def ok(text):print('OK:',text,flush=True)

with tempfile.TemporaryDirectory() as temp:
    work=Path(temp)
    for slot in range(4):
        folder=work/str(slot);folder.mkdir()
        disk=folder/'data.img';image(disk)
        v=VM(folder,disk_positions={slot:disk})
        try:
            v.cmd('disks',f'hd{chr(97+slot)} 65536 sectores | ATA LBA28')
            v.cmd('cat ata-marker.txt','ATA test')
            v.cmd('castctl write prueba.txt persistente')
            v.cmd('castctl memtest','Memoria: OK')
            v.cmd('castctl drvtest','OK')
        finally:v.close()
        verify(disk,'prueba.txt',b'persistente')
        v=VM(folder,disk_positions={slot:disk})
        try:v.cmd('cat prueba.txt','persistente')
        finally:v.close()
        ok(f'hd{chr(97+slot)}: deteccion, montaje, escritura exacta, espejo, reinicio, memoria y ABI')

    folder=work/'fallback';folder.mkdir()
    blank=folder/'blank.img';blank.write_bytes(bytes(32*1024*1024))
    disk=folder/'valid.img';image(disk)
    before=hashlib.sha256(blank.read_bytes()).digest()
    v=VM(folder,disk_positions={0:blank,3:disk})
    try:
        v.cmd('cat ata-marker.txt','ATA test')
        assert 'hdd 65536 sectores | ATA LBA28' in v.cmd('disks')
        v.cmd('castctl write correcto.txt elegido')
    finally:v.close()
    assert hashlib.sha256(blank.read_bytes()).digest()==before
    verify(disk,'correcto.txt',b'elegido')
    ok('hda vacio + hdd ASFS: elige volumen valido sin modificar hda')

    folder=work/'absent';folder.mkdir()
    v=VM(folder,disk_positions={})
    try:
        text=v.cmd('disks')
        assert 'hda 0 sectores | ausente' in text
        assert 'ATAPI (sin lectura optica)' in text
        assert 'RMFS disponible en /ram' in v.out()
    finally:v.close()
    ok('sin HDD: arranca en RAM; CD distinguido de disco ausente')

    folder=work/'large';folder.mkdir()
    disk=folder/'large.img';image(disk)
    with disk.open('r+b') as f:f.truncate(140*1024**3)
    v=VM(folder,disk_positions={0:disk})
    try:
        v.cmd('disks','hda 268435456 sectores | ATA LBA28')
        v.cmd('cat ata-marker.txt','ATA test')
        v.cmd('castctl write grande.txt grande')
    finally:v.close()
    verify(disk,'grande.txt',b'grande')
    ok('140 GiB: no se rechaza disco grande; ventana LBA28 de 128 GiB utilizable')

    # Boot the installer-created GRUB HDD from each secondary position.
    for slot in (2,3):
        folder=work/f'boot{slot}';folder.mkdir()
        data=folder/'data.img';image(data)
        disk=folder/'boot.img'
        subprocess.run(['python3',str(ROOT/'tools/install_disk.py'),str(disk),
                        '--data',str(data),'--target',f'hd{chr(97+slot)}'],check=True)
        v=VM(folder,boot_disk=True,disk_positions={slot:disk})
        try:v.cmd('cat ata-marker.txt','ATA test')
        finally:v.close()
        ok(f'GRUB HDD sin ISO: hd{chr(97+slot)}')

    # QEMU ide-hd rejects 4096-byte logical sectors (discard_granularity).
    # Keep the driver's IDENTIFY guard, but do not claim a hardware test.
    print('SKIP: 4Kn real no emulable por ide-hd de QEMU; guardia revisada, sin validacion fisica.',flush=True)
print('ATA detection suite passed.')
