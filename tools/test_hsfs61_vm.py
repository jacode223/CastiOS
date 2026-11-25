"""End-to-end HSFS6.1 QEMU test: requires a built x64 ISO and qemu-system-x86_64."""
import json
import os
import select
import shlex
import subprocess
import tempfile
import time
from pathlib import Path
from hsfs6 import mkfs, mkdir, put, stat, get
from vm_harness import ROOT

with tempfile.TemporaryDirectory() as temp:
    tmp = Path(temp)
    image = tmp / 'disk.img'
    log = tmp / 'debug.log'
    source = tmp / 'hello.txt'
    source.write_bytes(b'contenido desde HSFS6.1\n')
    mkfs(image, 1300 * 1024 * 1024)
    mkdir(image, '/docs')
    mkdir(image, '/docs/dev')
    put(image, '/docs/nota.txt', source)
    put(image, '/docs/dev/nota.txt', source)
    medium = tmp / 'medium.bin'
    medium.write_bytes((b'0123456789abcdef' * 131072) + b'FINMEDIO')
    put(image, '/docs/dev/medio.bin', medium)
    large = tmp / 'large.bin'
    with large.open('wb') as f:
        f.truncate(500 * 1024 * 1024)
        f.seek(500 * 1024 * 1024 - 8)
        f.write(b'FIN500MB')
    put(image, '/docs/dev/grande.bin', large)
    assert stat(image, '/docs/dev/grande.bin')[6] == 524288000
    get(image, '/docs/dev/grande.bin', tmp / 'tail.bin', offset=524287992, length=8)
    assert (tmp / 'tail.bin').read_bytes() == b'FIN500MB'
    cmd = ['qemu-system-x86_64', '-m', '256', '-accel', 'tcg',
           '-display', 'none', '-serial', 'none', '-monitor', 'none',
           '-nic', 'none', '-no-reboot', '-boot', 'd',
           '-cdrom', str(ROOT / 'dist/CastiOS-x64-preview.iso'),
           '-drive', f'file={image},format=raw,if=ide,index=0',
           '-qmp', 'stdio', '-debugcon', f'file:{log}']
    cmd += shlex.split(os.environ.get('QEMU_EXTRA_ARGS', ''))
    vm = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, bufsize=0)

    def qmp(request, arguments=None):
        data = {'execute': request}
        if arguments:
            data['arguments'] = arguments
        vm.stdin.write(json.dumps(data).encode() + b'\n')
        while True:
            assert select.select([vm.stdout], [], [], 15)[0], 'QMP sin respuesta'
            result = json.loads(vm.stdout.readline())
            assert 'error' not in result, result
            if 'return' in result:
                return result

    def wait(expected, start=0, attempts=900):
        for _ in range(attempts):
            data = log.read_text(errors='replace') if log.exists() else ''
            if expected in data[start:]:
                return
            time.sleep(0.02)
        raise AssertionError((expected, data[-1500:]))

    def command(value, expected, attempts=900):
        start = len(log.read_text())
        for ch in value:
            key = {' ': 'spc', '.': 'dot', '/': 'slash', '-': 'minus',
                   '>': 'shift-dot'}.get(ch, ch)
            qmp('human-monitor-command', {'command-line': f'sendkey {key} 30'})
            time.sleep(.012)
        qmp('human-monitor-command', {'command-line': 'sendkey ret 30'})
        wait(expected, start, attempts)

    try:
        assert select.select([vm.stdout], [], [], 15)[0]
        json.loads(vm.stdout.readline())
        qmp('qmp_capabilities')
        wait('x64> ')
        command('mount', 'HSFS6 montado')
        command('ls', 'docs/')
        command('ls docs', 'nota.txt')
        command('cd docs', 'x64> ')
        command('pwd', '/docs')
        command('cat nota.txt', 'contenido desde HSFS6.1')
        command('read6 nota.txt 10 5', 'desde')
        command('cd dev', 'x64> ')
        command('pwd', '/docs/dev')
        command('stat grande.bin', 'bytes=524288000')
        command('read6 grande.bin 524287992 8', 'FIN500MB')
        command('cp nota.txt copia.txt', 'Copia terminada')
        command('cat copia.txt', 'contenido desde HSFS6.1')
        command('cp medio.bin medio2.bin', 'Copia terminada', attempts=4500)
        command('stat medio2.bin', 'bytes=2097160')
        command('read6 medio2.bin 2097152 8', 'FINMEDIO')
        if os.environ.get('HSFS_FULL_COPY') == '1':
            command('cp grande.bin copia.bin', 'Copia terminada', attempts=45000)
            command('stat copia.bin', 'bytes=524288000')
            command('read6 copia.bin 524287992 8', 'FIN500MB')
        command('mkdir sub', 'directorio creado')
        command('cd sub', 'x64> ')
        command('echo hola > nuevo.txt', 'archivo guardado')
        command('cat nuevo.txt', 'hola')
        command('filesys', 'Proceso CPL3 terminado con EAX=7')
        command('cd /', 'x64> ')
        command('ls /docs/dev/sub', 'nuevo.txt')
        command('stat /docs/dev/sub/nuevo.txt', 'bytes=5')
        command('mount6', 'HSFS6 montado')
        command('cat docs/dev/sub/nuevo.txt', 'hola')
    finally:
        vm.terminate()
        try:
            vm.wait(timeout=5)
        except subprocess.TimeoutExpired:
            vm.kill()
            vm.wait()
    assert stat(image, '/docs/dev/sub/nuevo.txt')[6] == 5
    get(image, '/docs/dev/sub/nuevo.txt', tmp / 'new-file.txt')
    assert (tmp / 'new-file.txt').read_bytes() == b'hola\n'
    get(image, '/docs/dev/medio2.bin', tmp / 'copied-medium.bin')
    assert (tmp / 'copied-medium.bin').read_bytes() == medium.read_bytes()
    if os.environ.get('HSFS_FULL_COPY') == '1':
        copied=stat(image, '/docs/dev/copia.bin')
        assert copied[6] == 500 * 1024 * 1024
        with image.open('rb') as disk, large.open('rb') as original:
            disk.seek(copied[7] * 512)
            remaining=copied[6]
            while remaining:
                count=min(1024*1024, remaining)
                assert disk.read(count)==original.read(count)
                remaining-=count

print('HSFS6.1 QEMU: rutas, cd/pwd, mkdir, lectura parcial, escritura y remount: OK')
