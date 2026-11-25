#!/usr/bin/env python3
"""HSFS 6.1: mirrored metadata, hierarchical directories, 64-bit file lengths.

Layout compatible with HSFS6 (minor=0) for read and root-file writes. 6.1
keeps header major=6 and sets minor=1 at offset 48.  Records use offset 96
for the parent directory ID (record index + 1; root=0).  Payloads are
contiguous extents; host operations stream in 1 MiB chunks, never buffering
whole large files.  The last committed AND previous generations' extents are
reserved until obsolete to preserve recovery after interrupted updates.
"""
import argparse
import os
import re
import struct
from pathlib import Path

SECTOR = 512
COUNT = 128
RECORD = 128
TABLE_SIZE = COUNT * RECORD
HEADER_LBA = (8, 9)
TABLE_LBA = (16, 48)
DATA_START = 80
MAGIC = b'HSFS6\0\0\0'
NAME = re.compile(rb'[A-Za-z0-9_.-]{1,63}\Z')
CHUNK = 1024 * 1024
KIND_FILE = 1
KIND_DIR = 2


def checksum(data):
    return sum(data) & 0xFFFFFFFF


def header(generation, sectors, table, index, minor=0, next_lba=DATA_START):
    b = bytearray(SECTOR)
    struct.pack_into('<8sIIQQQII', b, 0, MAGIC, 6, SECTOR, generation,
                     sectors, TABLE_LBA[index], checksum(table), 0)
    struct.pack_into('<I', b, 48, minor)
    struct.pack_into('<Q', b, 56, next_lba)
    struct.pack_into('<I', b, 44, checksum(b))
    return b


def entries(table):
    for i in range(COUNT):
        off = i * RECORD
        if not table[off]:
            continue
        raw = table[off:off + RECORD]
        name = bytes(raw[:64]).split(b'\0', 1)[0]
        kind, uid, gid, mode = struct.unpack_from('<IIII', raw, 64)
        size, start = struct.unpack_from('<QQ', raw, 80)
        parent = struct.unpack_from('<I', raw, 96)[0]
        yield i, name, kind, uid, gid, mode, size, start, parent


def validate_table(table, total, minor):
    """Reject invalid names, duplicate siblings, cycles and data overlaps."""
    if minor not in (0, 1) or total < DATA_START or len(table) != TABLE_SIZE:
        raise ValueError('Version, capacidad o tabla invalidos')
    records = list(entries(table))
    by_id = {i + 1: (name, kind, parent) for i, name, kind, *_, parent in records}
    siblings = set()
    intervals = []
    for i, name, kind, uid, gid, mode, size, start, parent in records:
        if not NAME.fullmatch(name) or name in (b'.', b'..'):
            raise ValueError('Nombre de archivo/directorio invalido')
        if (parent, name) in siblings:
            raise ValueError('Nombres repetidos en la misma carpeta')
        siblings.add((parent, name))
        if minor == 0 and (parent != 0 or kind != KIND_FILE):
            raise ValueError('Un volumen HSFS6 antiguo no permite carpetas')
        if kind not in (KIND_FILE, KIND_DIR):
            raise ValueError('Tipo de entrada no soportado')
        if kind == KIND_DIR and (minor != 1 or size != 0 or start != DATA_START):
            raise ValueError('Directorio invalido')
        if parent and (parent not in by_id or by_id[parent][1] != KIND_DIR):
            raise ValueError('Directorio padre no encontrado')
        if kind == KIND_FILE:
            n = (size + SECTOR - 1) // SECTOR
            if start < DATA_START or start > total or n > total - start:
                raise ValueError('Extension fuera del volumen')
            if n:
                intervals.append((start, start + n))
        # Reject cycles even when the on-disk table is deliberately corrupted.
        visited = {i + 1}
        ancestor = parent
        while ancestor:
            if ancestor in visited or ancestor not in by_id:
                raise ValueError('Jerarquia ciclica o rota')
            visited.add(ancestor)
            ancestor = by_id[ancestor][2]
    intervals.sort()
    for a, b in zip(intervals, intervals[1:]):
        if a[1] > b[0]:
            raise ValueError('Extensiones de archivos solapadas')


def _slot(f, index):
    f.seek(HEADER_LBA[index] * SECTOR)
    h = f.read(SECTOR)
    if len(h) != SECTOR:
        return None
    magic, version, sector, gen, total, table_lba, table_sum, hsum = struct.unpack_from('<8sIIQQQII', h)
    minor = struct.unpack_from('<I', h, 48)[0]
    if magic != MAGIC or version != 6 or sector != SECTOR or table_lba != TABLE_LBA[index]:
        return None
    copy = bytearray(h)
    struct.pack_into('<I', copy, 44, 0)
    watermark = struct.unpack_from('<Q', h, 56)[0]
    if checksum(copy) != hsum or total < DATA_START or watermark > total:
        return None
    f.seek(0, os.SEEK_END)
    if total > f.tell() // SECTOR:
        return None
    f.seek(table_lba * SECTOR)
    table = bytearray(f.read(TABLE_SIZE))
    if len(table) != TABLE_SIZE or checksum(table) != table_sum:
        return None
    try:
        validate_table(table, total, minor)
    except ValueError:
        return None
    return gen, total, table, index, minor


def read_slot(f, index):
    """Historic 4-item interface retained for existing CastiOS scripts."""
    entry = _slot(f, index)
    return entry[:4] if entry is not None else None


def _mount(f):
    slots = [x for x in (_slot(f, 0), _slot(f, 1)) if x is not None]
    if not slots:
        raise ValueError('No hay copia HSFS6 valida')
    return max(slots, key=lambda x: x[0])


def mount(f):
    return _mount(f)[:4]


def mkfs(path, size, minor=1):
    path = Path(path)
    if size < 1024 * 1024 or size % SECTOR:
        raise ValueError('Tamano minimo 1 MiB y multiplo de 512')
    if minor not in (0, 1):
        raise ValueError('Version menor invalida')
    with path.open('xb') as f:  # never overwrite a disk implicitly
        f.truncate(size)
        empty = bytes(TABLE_SIZE)
        for i in (0, 1):
            f.seek(TABLE_LBA[i] * SECTOR)
            f.write(empty)
            f.seek(HEADER_LBA[i] * SECTOR)
            f.write(header(0, size // SECTOR, empty, i, minor))
        f.flush()
        os.fsync(f.fileno())


def normalize(path):
    if not path or '\\' in path or '\0' in path:
        raise ValueError('Ruta invalida')
    parts = []
    for comp in path.split('/'):
        if comp in ('', '.'):
            continue
        if comp == '..':
            if parts:
                parts.pop()
            continue
        raw = comp.encode('ascii')
        if not NAME.fullmatch(raw):
            raise ValueError(f'Nombre invalido: {comp!r}')
        parts.append(raw)
    return parts


def resolve(table, path):
    parts = normalize(path)
    parent = 0
    chosen = None
    for idx, part in enumerate(parts):
        chosen = next((item for item in entries(table)
                       if item[8] == parent and item[1] == part), None)
        if chosen is None:
            raise FileNotFoundError(path)
        if idx + 1 < len(parts) and chosen[2] != KIND_DIR:
            raise NotADirectoryError(path)
        parent = chosen[0] + 1
    return chosen  # None = /


def record(table, slot, name, kind, size=0, start=DATA_START, parent=0, mode=0o644):
    off = slot * RECORD
    table[off:off + RECORD] = bytes(RECORD)
    table[off:off + len(name)] = name
    struct.pack_into('<IIIIQQI', table, off + 64, kind, 0, 0, mode, size, start, parent)


def free_slot(table, preferred=None):
    if preferred is not None:
        return preferred
    for i in range(COUNT):
        if not table[i * RECORD]:
            return i
    raise ValueError('Tabla llena: limite de 128 entradas')


def _reserved_extents(f, active_table):
    """Protect both valid snapshots, not just the active one."""
    blocks = []
    for slot in (0, 1):
        snapshot = _slot(f, slot)
        if snapshot is None:
            continue
        for item in entries(snapshot[2]):
            if item[2] != KIND_FILE:
                continue
            n = (item[6] + SECTOR - 1) // SECTOR
            if n:
                blocks.append((item[7], item[7] + n))
    return sorted(blocks)


def allocate(f, total, sectors, start_override=None):
    intervals = _reserved_extents(f, None)
    if start_override is not None:
        s = start_override
        if s < DATA_START or s > total or sectors > total - s:
            raise ValueError('Sin espacio o LBA fuera del volumen')
        if any(s < end and begin < s + sectors for begin, end in intervals):
            raise ValueError('La ubicacion solicitada pisa datos confirmados')
        return s
    candidate = DATA_START
    for begin, end in intervals:
        if candidate + sectors <= begin:
            break
        candidate = max(candidate, end)
    if candidate > total or sectors > total - candidate:
        raise ValueError('Sin espacio para el archivo')
    return candidate


def commit(f, generation, total, table, active, minor):
    validate_table(table, total, minor)
    # Keep a monotonic allocation watermark for the kernel's append-only writer.
    f.seek(HEADER_LBA[active] * SECTOR + 56)
    previous_high = struct.unpack('<Q', f.read(8))[0]
    high = max(DATA_START, previous_high)
    for item in entries(table):
        if item[2] == KIND_FILE:
            high = max(high, item[7] + (item[6] + SECTOR - 1) // SECTOR)
    for begin, end in _reserved_extents(f, table):
        high = max(high, end)
    target = 1 - active
    f.seek(TABLE_LBA[target] * SECTOR)
    f.write(table)
    f.flush()
    os.fsync(f.fileno())
    f.seek(HEADER_LBA[target] * SECTOR)
    f.write(header(generation + 1, total, table, target, minor, high))
    f.flush()
    os.fsync(f.fileno())


def mkdir(path, dirname):
    with Path(path).open('r+b') as f:
        generation, total, table, active, minor = _mount(f)
        if minor != 1:
            raise ValueError('mkfs --legacy no tiene directorios')
        parts = normalize(dirname)
        if not parts:
            raise ValueError('La raiz ya existe')
        try:
            resolve(table, dirname)
        except FileNotFoundError:
            pass
        else:
            raise FileExistsError(dirname)
        parent_path = b'/'.join(parts[:-1]).decode('ascii')
        parent = resolve(table, parent_path) if parent_path else None
        if parent and parent[2] != KIND_DIR:
            raise NotADirectoryError(parent_path)
        slot = free_slot(table)
        record(table, slot, parts[-1], KIND_DIR, parent=parent[0] + 1 if parent else 0, mode=0o755)
        commit(f, generation, total, table, active, minor)


def put(path, name, src, start_override=None):
    src = Path(src)
    size = src.stat().st_size
    parts = normalize(name)
    if not parts:
        raise ValueError('No se puede escribir en /')
    with Path(path).open('r+b') as f:
        generation, total, table, active, minor = _mount(f)
        if minor == 0 and len(parts) != 1:
            raise ValueError('El formato HSFS6 original solo permite raiz')
        parent_path = b'/'.join(parts[:-1]).decode('ascii')
        parent = resolve(table, parent_path) if parent_path else None
        if parent is not None and parent[2] != KIND_DIR:
            raise NotADirectoryError(parent_path)
        existing = None
        try:
            existing = resolve(table, name)
        except FileNotFoundError:
            pass
        if existing and existing[2] != KIND_FILE:
            raise IsADirectoryError(name)
        slot = free_slot(table, existing[0] if existing else None)
        sectors = (size + SECTOR - 1) // SECTOR
        start = allocate(f, total, sectors, start_override)
        f.seek(start * SECTOR)
        with src.open('rb') as source:
            while True:
                block = source.read(CHUNK)
                if not block:
                    break
                f.write(block)
        if size % SECTOR:
            f.write(bytes(SECTOR - size % SECTOR))
        f.flush()
        os.fsync(f.fileno())
        record(table, slot, parts[-1], KIND_FILE, size, start,
               parent=parent[0] + 1 if parent else 0)
        commit(f, generation, total, table, active, minor)


def get(path, name, output, offset=0, length=None):
    if offset < 0 or length is not None and length < 0:
        raise ValueError('Offset o longitud negativos')
    with Path(path).open('rb') as f:
        _, _, table, _, _ = _mount(f)
        item = resolve(table, name)
        if item is None or item[2] != KIND_FILE:
            raise IsADirectoryError(name)
        size, start = item[6], item[7]
        remaining = min(size - min(offset, size), length if length is not None else size)
        f.seek(start * SECTOR + min(offset, size))
        with Path(output).open('xb') as out:
            while remaining:
                chunk = f.read(min(CHUNK, remaining))
                if not chunk:
                    raise OSError('Disco truncado al leer el archivo')
                out.write(chunk)
                remaining -= len(chunk)


def listing(path, dirname='/'):
    with Path(path).open('rb') as f:
        generation, total, table, active, minor = _mount(f)
        parent = resolve(table, dirname)
        if parent and parent[2] != KIND_DIR:
            raise NotADirectoryError(dirname)
        directory_id = parent[0] + 1 if parent else 0
        rows = [(item[1].decode('ascii') + ('/' if item[2] == KIND_DIR else ''), item[6], item[7])
                for item in entries(table) if item[8] == directory_id]
        return generation, total, active, minor, rows


def stat(path, name):
    with Path(path).open('rb') as f:
        _, _, table, _, _ = _mount(f)
        return resolve(table, name)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest='cmd', required=True)
    p = sub.add_parser('mkfs'); p.add_argument('image', type=Path)
    p.add_argument('--size-mib', type=int, default=64)
    p.add_argument('--legacy', action='store_true', help='crear HSFS6 v1 (sin carpetas)')
    p = sub.add_parser('put'); p.add_argument('image', type=Path)
    p.add_argument('name'); p.add_argument('source', type=Path); p.add_argument('--start-lba', type=int)
    p = sub.add_parser('get'); p.add_argument('image', type=Path)
    p.add_argument('name'); p.add_argument('output', type=Path)
    p.add_argument('--offset', type=int, default=0); p.add_argument('--length', type=int)
    p = sub.add_parser('mkdir'); p.add_argument('image', type=Path); p.add_argument('name')
    p = sub.add_parser('ls'); p.add_argument('image', type=Path); p.add_argument('name', nargs='?', default='/')
    p = sub.add_parser('stat'); p.add_argument('image', type=Path); p.add_argument('name')
    args = ap.parse_args()
    try:
        if args.cmd == 'mkfs':
            mkfs(args.image, args.size_mib * 1024 * 1024, minor=0 if args.legacy else 1)
        elif args.cmd == 'put':
            put(args.image, args.name, args.source, args.start_lba)
        elif args.cmd == 'get':
            get(args.image, args.name, args.output, args.offset, args.length)
        elif args.cmd == 'mkdir':
            mkdir(args.image, args.name)
        elif args.cmd == 'stat':
            item = stat(args.image, args.name)
            if item is None: print('raiz: /')
            else: print(f'tipo={"directorio" if item[2]==2 else "archivo"} bytes={item[6]} lba={item[7]} padre={item[8]}')
        else:
            generation, total, active, minor, rows = listing(args.image, args.name)
            print(f'HSFS6.{minor} generacion={generation} sectores={total} copia={active} carpeta={args.name}')
            for name, size, start in rows:
                print(f'{name:64} {size:>14} bytes  lba={start}')
    except (OSError, ValueError, UnicodeError) as exc:
        ap.error(str(exc))


if __name__ == '__main__':
    main()
