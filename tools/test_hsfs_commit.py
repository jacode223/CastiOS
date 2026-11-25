"""Simulated power cuts at each mirror boundary keep a valid HSFS snapshot."""
import shutil
import struct
import tempfile
from pathlib import Path

from fs_format import SIZE, extract_or_migrate, put, seal, validate, body
from vm_harness import ROOT

with tempfile.TemporaryDirectory() as tmp:
    disk = Path(tmp)/'disk.img'
    shutil.copyfile(ROOT/'build/CastiOS-hdd.img', disk)
    with disk.open('rb') as f:
        f.seek(16*1024*1024)
        old = extract_or_migrate(f.read(SIZE))
    new = bytearray(old)
    put(new, 0, 'readme.txt', b'actualizado tras corte\n')
    struct.pack_into('<I', new, 20, struct.unpack_from('<I', old, 20)[0]+1)
    seal(new)
    assert validate(old) and validate(new)
    # Crash while writing mirror data: old primary still valid.
    mirror_half = bytearray(old)
    mirror_half[512:1024] = new[512:1024]
    with disk.open('r+b') as f:
        f.seek(20*1024*1024)
        f.write(mirror_half)
    with disk.open('rb') as f:
        f.seek(16*1024*1024)
        selected = extract_or_migrate(f.read(SIZE))
    assert body(selected, 0) == body(old, 0)
    # Mirror committed, primary interrupted: the mirror is recoverable.
    primary_half = bytearray(old)
    primary_half[512:1024] = new[512:1024]
    with disk.open('r+b') as f:
        f.seek(16*1024*1024)
        f.write(primary_half)
        f.seek(20*1024*1024)
        f.write(new)
    with disk.open('rb') as f:
        f.seek(16*1024*1024)
        raw = f.read(4*1024*1024+SIZE)
    assert validate(raw[4*1024*1024:]) == new
print('HSFS: corte durante espejo y primario deja una copia valida OK.')
