"""Install editable NASM sources and prebuilt dependencies into a HSFS disk.

Run only with the VM powered off. Existing source files are never overwritten.
"""
import argparse
import struct
from pathlib import Path

from fs_format import COUNT, RECORD, ROOT, SIZE, extract_or_migrate, put, seal, validate

HERE = Path(__file__).resolve().parent.parent
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('disk', type=Path)
p.add_argument('--refresh', action='store_true', help='replace shipped sources (only for release builds)')
args = p.parse_args()
if not args.disk.is_file():
    p.error('Disco inexistente')
items = list((HERE / 'src').rglob('*')) + list((HERE / 'docs/on_disk').rglob('*'))
items += [HERE / 'build/nasm_runtime.bin', HERE / 'build/speed_user.bin', HERE / 'build/hddboot.bin']
items = [(x, x.relative_to(HERE).parts) for x in items if x.is_file()]
# NASM first searches relative to the including file's directory. The
# generated installed_docs.asm resides in /src and names docs/on_disk/...
items += [(x, ('src', 'docs', 'on_disk', x.name))
          for x in (HERE / 'docs/on_disk').glob('*.TXT')]
items.sort(key=lambda pair: pair[1])
with args.disk.open('r+b') as disk:
    disk.seek(16 * 1024 * 1024)
    fs = extract_or_migrate(disk.read(SIZE))
    paths = {(): ROOT}

    def find(parent, name):
        for i in range(COUNT):
            off = 512 + i * RECORD
            if fs[off] and struct.unpack_from('<I', fs, off + 32)[0] == parent:
                if bytes(fs[off:off+32]).split(b'\0', 1)[0] == name.encode():
                    return i
        return None

    def slot():
        return next((i for i in range(COUNT) if not fs[512+i*RECORD]), None)

    for path, parts in items:
        for level in range(1, len(parts)):
            prefix = parts[:level]
            if prefix in paths:
                continue
            parent = paths[prefix[:-1]]
            index = find(parent, prefix[-1])
            if index is None:
                index = slot()
                if index is None:
                    raise SystemExit('HSFS lleno antes de crear directorios')
                put(fs, index, prefix[-1], parent=parent, kind=2)
            elif struct.unpack_from('<I', fs, 512+index*RECORD+36)[0] != 2:
                raise SystemExit(f'No es directorio: {prefix}')
            paths[prefix] = index
        parent = paths[parts[:-1]]
        existing = find(parent, parts[-1])
        if existing is not None and not args.refresh:
            continue
        index = existing if existing is not None else slot()
        if index is None:
            raise SystemExit('HSFS lleno antes de copiar fuentes')
        data = path.read_bytes()
        put(fs, index, parts[-1], data, parent=parent,
            kind=3 if path.suffix == '.bin' else 1)
    fs = validate(seal(fs))
    for off in (16 * 1024 * 1024, 20 * 1024 * 1024):
        disk.seek(off)
        disk.write(fs)
print(f'Fuentes NASM instalados en {args.disk}; archivos existentes conservados.')
