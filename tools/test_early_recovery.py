"""A trial boot selects stable before reading either HSFS mirror."""
import shutil
import tempfile
from pathlib import Path
from vm_harness import ROOT, VM

with tempfile.TemporaryDirectory() as t:
    work=Path(t)
    disk=work/'broken.img'
    shutil.copyfile(ROOT/'build/CastiOS-hdd.img',disk)
    with disk.open('r+b') as f:
        f.seek(696*512+12);f.write(b'1')
        f.seek(696*512+32);f.write(b'P')
        for offset in (16*1024*1024,20*1024*1024):
            f.seek(offset);f.write(b'BROKEN-HSFS!')
    v=VM(work,disk,boot_disk=True,memory=200)
    try:
        output=v.out()
        assert 'Recuperacion: siguiente arranque estable antes del montaje HSFS.' in output,output[-2500:]
        assert 'RMFS disponible en /ram; datos temporales' in output,output[-2500:]
        v.cmd('echo shell-viva','shell-viva')
    finally:v.close()
    with disk.open('rb') as f:
        f.seek(696*512);slot=f.read(64)
        assert slot[12:13]==b'0' and slot[32:33]==b'R',slot
        for offset in (16*1024*1024,20*1024*1024):
            f.seek(offset);assert f.read(12)==b'BROKEN-HSFS!'
    # A second boot uses the stable entry, despite invalid FS on both banks.
    work2=work/'second';work2.mkdir()
    v=VM(work2,disk,boot_disk=True,memory=200)
    try:
        assert 'Recuperacion: siguiente arranque' not in v.out()
        v.cmd('echo estable','estable')
    finally:v.close()
print('Boot A/B: prueba con HSFS doblemente corrupto revierte a Estable y deja el disco intacto.')
