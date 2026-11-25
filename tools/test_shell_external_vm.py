"""Boot a writable HSFS6 disk and create, run and recover CPL3 shells."""
import json, os, select, shlex, subprocess, tempfile, time
from pathlib import Path
from hsfs6 import mkfs, put
ROOT = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory() as temp:
    temp = Path(temp); image = temp/'disk.img'; log = temp/'debug.log'
    mkfs(image, 32*1024*1024)
    (temp/'bad').write_bytes(b'not a shell')
    (temp/'fault').write_bytes(b'\xeb\x04CSH1\x0f\x0b')
    put(image, '/invalid', temp/'bad'); put(image, '/fault', temp/'fault')
    (temp/'multi').write_bytes(b'print uno\nprint dos\n')
    (temp/'wrong').write_bytes(b'print valido\nvariable = 3\n')
    (temp/'large').write_bytes(b'print ' + b'x'*251)
    (temp/'expand').write_bytes(b'print x\n'*30)
    put(image, '/multi', temp/'multi'); put(image, '/wrong', temp/'wrong')
    put(image, '/large', temp/'large'); put(image, '/expand', temp/'expand')
    source = (ROOT/'examples/shell64/shell.asm').read_text().replace("prompt db 'propia> '", "prompt db 'externa> '")
    (temp/'external.asm').write_text(source)
    subprocess.run(['nasm', '-f', 'bin', str(temp/'external.asm'), '-o', str(temp/'external.bin')], check=True)
    put(image, '/external', temp/'external.bin')
    args=['qemu-system-x86_64','-m','256','-accel','tcg','-display','none',
          '-serial','none','-monitor','none','-nic','none','-no-reboot','-boot','d',
          '-cdrom',str(ROOT/'dist/CastiOS-x64-preview.iso'),
          '-drive',f'file={image},format=raw,if=ide,index=0',
          '-qmp','stdio','-debugcon','file:'+str(log)]
    args += shlex.split(os.environ.get('QEMU_EXTRA_ARGS',''))
    vm=subprocess.Popen(args,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,bufsize=0)
    def qmp(cmd, args=None):
        vm.stdin.write((json.dumps({'execute':cmd,'arguments':args or {}})+'\n').encode())
        while True:
            assert select.select([vm.stdout],[],[],15)[0], 'QMP timeout'
            answer=json.loads(vm.stdout.readline())
            assert 'error' not in answer, answer
            if 'return' in answer: return answer['return']
    def wait(needle,start=0):
        for _ in range(1200):
            data=log.read_text(errors='replace') if log.exists() else ''
            if needle in data[start:]: return data[start:]
            time.sleep(.02)
        raise AssertionError((needle,data[-2000:]))
    def command(line, expected):
        start=len(log.read_text())
        for ch in line:
            key={' ':'spc','/':'slash','.':'dot','-':'minus','>':'shift-dot'}.get(ch,ch)
            qmp('human-monitor-command',{'command-line':f'sendkey {key} 35'})
            time.sleep(.025)
        qmp('human-monitor-command',{'command-line':'sendkey ret 35'})
        return wait(expected,start)
    try:
        assert select.select([vm.stdout],[],[],15)[0]
        json.loads(vm.stdout.readline()); qmp('qmp_capabilities'); wait('x64> ')
        assert 'Monta' in command('shell new /custom','x64> ')
        command('mount','HSFS6 montado')
        assert 'guardado' in command('echo print hola > /saludo', 'x64> ')
        assert 'compilado' in command('castic /saludo /hola', 'x64> ')
        assert 'hola' in command('shell run /hola', 'x64> ')
        assert 'destino existe' in command('castic /saludo /hola', 'x64> ')
        assert 'sintaxis invalida' in command('castic /wrong /error', 'x64> ')
        assert 'No se puede cargar' in command('shell run /error', 'x64> ')
        assert 'fuente >256 bytes' in command('castic /large /too', 'x64> ')
        assert 'excede 511' in command('castic /expand /big', 'x64> ')
        assert 'compilado' in command('castic /multi /dos', 'x64> ')
        out = command('shell run /dos', 'x64> ')
        assert 'uno\ndos\n' in out, out
        assert 'guardado' in command('shell new /custom','x64> ')
        assert 'ya existe' in command('shell new /custom','x64> ')
        assert 'No se puede cargar' in command('shell run /invalid','x64> ')
        assert 'fallo' in command('shell run /fault','x64> ')
        command('shell run /custom','propia> ')
        assert 'help exit' in command('help','propia> ')
        assert 'desconocido' in command('nope','propia> ')
        assert 'recuperada' in command('exit','x64> ')
        command('shell run /external','externa> ')
        assert 'recuperada' in command('exit','x64> ')
        command('mount','HSFS6 montado')
        command('shell run /custom','propia> ')
        assert 'recuperada' in command('exit','x64> ')
        print('Shell CPL3: create, persist, input, run and fault recovery OK')
    finally:
        vm.terminate()
        try: vm.wait(timeout=5)
        except subprocess.TimeoutExpired: vm.kill(); vm.wait()
