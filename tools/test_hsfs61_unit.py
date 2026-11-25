"""Host-only HSFS6.1 filesystem tests. Run with python3 tools/test_hsfs61_unit.py."""
from pathlib import Path
import os
import struct
import tempfile
from hsfs6 import mkfs, mkdir, put, get, mount, listing, stat, resolve, header, TABLE_LBA, HEADER_LBA, SECTOR, read_slot


def check_failure(fn, exc=Exception):
    try:
        fn()
    except exc:
        return
    raise AssertionError(f'{fn!r} should have failed')


with tempfile.TemporaryDirectory() as work:
    p = Path(work)
    img = p / 'disk.img'
    mkfs(img, 128 * 1024 * 1024)
    mkdir(img, 'etc')
    mkdir(img, 'etc/config')
    mkdir(img, 'home')
    mkdir(img, 'home/etc')
    a = p / 'short.txt'
    a.write_bytes(b'Hola HSFS6.1\n')
    put(img, '/etc/config/hello.txt', a)
    put(img, 'home/etc/hello.txt', a)
    assert [x[0] for x in listing(img, '/')[4]] == ['etc/', 'home/']
    assert [x[0] for x in listing(img, '/etc')[4]] == ['config/']
    assert listing(img, '/etc/config')[4][0][0] == 'hello.txt'
    get(img, 'etc/config/hello.txt', p / 'read.txt')
    assert (p / 'read.txt').read_bytes() == b'Hola HSFS6.1\n'
    check_failure(lambda: mkdir(img, '/etc'), FileExistsError)
    check_failure(lambda: put(img, 'etc/xxx/x', a), FileNotFoundError)
    check_failure(lambda: put(img, 'etc/config', a), IsADirectoryError)
    check_failure(lambda: mkdir(img, 'etc/config/..'), FileExistsError)
    check_failure(lambda: mkdir(img, 'etc/config/hello.txt/xx'), NotADirectoryError)

    # Streaming a file longer than 1 MiB: offset/length extraction, no truncation.
    big = p / 'big.bin'
    large_size = 101 * 1024 * 1024 + 7
    with big.open('wb') as f:
        f.truncate(large_size)
        f.seek(2**20 - 3)
        f.write(b'0123456789abcdef' * 3)
        f.seek(large_size - 7)
        f.write(b'finish!')
    put(img, '/home/big.bin', big)
    get(img, '/home/big.bin', p / 'part.bin', offset=2**20 - 3, length=33)
    assert (p / 'part.bin').read_bytes() == (b'0123456789abcdef' * 3)[:33]
    get(img, '/home/big.bin', p / 'end.bin', offset=large_size - 7, length=7)
    assert (p / 'end.bin').read_bytes() == b'finish!'
    assert stat(img, '/home/big.bin')[6] == large_size

    # Overwrite while snapshots still protect committed old payload.
    old = stat(img, '/home/big.bin')
    a.write_bytes(b'replaced, still valid\n')
    put(img, '/home/big.bin', a)
    new = stat(img, '/home/big.bin')
    assert old[7] != new[7]
    get(img, '/home/big.bin', p / 'replaced.txt')
    assert (p / 'replaced.txt').read_bytes() == a.read_bytes()

    # Corrupt active header, fallback must recover previous directory tree.
    with img.open('r+b') as f:
        generation, total, table, active = mount(f)
        assert generation == 8
        f.seek(HEADER_LBA[active] * SECTOR)
        f.write(b'BAD!')
        f.flush()
        os.fsync(f.fileno())
        assert mount(f)[0] == generation - 1
    assert stat(img, '/home/big.bin')[6] == large_size

    # Reject a cycle even with a recalculated table checksum.
    with img.open('r+b') as f:
        generation, total, table, active = mount(f)
        # etc is record 0 -> parent self (id 1).
        struct.pack_into('<I', table, 96, 1)
        f.seek(TABLE_LBA[active] * SECTOR)
        f.write(table)
        f.seek(HEADER_LBA[active] * SECTOR)
        f.write(header(generation, total, table, active, minor=1))
        assert read_slot(f, active) is None

    # Version 6 legacy images remain mountable and writable at root.
    legacy = p / 'legacy.img'
    mkfs(legacy, 2 * 1024 * 1024, minor=0)
    put(legacy, 'hello.txt', a)
    assert listing(legacy)[3] == 0
    check_failure(lambda: mkdir(legacy, 'etc'), ValueError)
    check_failure(lambda: put(legacy, 'etc/xx', a), ValueError)

    # Sparse image: 64-bit LBA addresses beyond 4GiB.
    sparse = p / 'sparse.img'
    mkfs(sparse, 6 * 1024**3)
    put(sparse, 'far.bin', a, start_override=8388610)
    assert stat(sparse, 'far.bin')[7] == 8388610
    get(sparse, 'far.bin', p / 'far.read')
    assert (p / 'far.read').read_bytes() == a.read_bytes()

print('HSFS6.1: hierarchy, large streamed files, ranges, recovery, corruption, v6 legacy and 64-bit LBAs: OK')
