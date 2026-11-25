"""Boot x64 and exercise switching/filtering, compatibility and CPL3 ABI."""
import json, os, shlex, subprocess, tempfile, time
from pathlib import Path
root = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory() as tmp:
    log = Path(tmp) / 'debug.log'
    cmd = ['qemu-system-x86_64', '-accel', 'tcg', '-display', 'none',
           '-serial', 'none', '-monitor', 'none', '-nic', 'none', '-no-reboot',
           '-boot', 'd', '-cdrom', str(root/'dist/CastiOS-x64-preview.iso'),
           '-qmp', 'stdio', '-debugcon', 'file:'+str(log)]
    cmd += shlex.split(os.environ.get('QEMU_EXTRA_ARGS', ''))
    vm = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    def qmp(command, args=None):
        vm.stdin.write((json.dumps({'execute':command, 'arguments':args or {}})+'\n').encode()); vm.stdin.flush()
        while True:
            reply = json.loads(vm.stdout.readline())
            if 'error' in reply: raise AssertionError(reply)
            if 'return' in reply: return reply['return']
    def wait_for(needle, start=0):
        deadline = time.monotonic()+30
        while time.monotonic() < deadline:
            text = log.read_text(errors='replace') if log.exists() else ''
            if needle in text[start:]: return text[start:]
            time.sleep(.05)
        raise AssertionError(f'missing {needle!r}: {text[start:]!r}')
    def command(line, prompt):
        start = log.stat().st_size
        for ch in line:
            key = {' ': 'spc'}.get(ch, ch)
            qmp('human-monitor-command', {'command-line':f'sendkey {key} 30'})
            time.sleep(.025)
        qmp('human-monitor-command', {'command-line':'sendkey ret 30'})
        return wait_for(prompt, start)
    try:
        json.loads(vm.stdout.readline()); qmp('qmp_capabilities'); wait_for('x64> ')
        assert 'classic, rescue' in command('shell list', 'x64> ')
        assert 'cambiada' in command('shell rescue', 'rescue> ')
        assert 'CastiOS x86-64' in command('uname', 'rescue> ')
        assert 'no disponible' in command('install', 'rescue> ')
        assert 'no disponible' in command('mkdir unsafe', 'rescue> ')
        assert 'cambiada' in command('shell classic', 'x64> ')
        assert 'EAX=0' in command('syscheck', 'x64> ')
        assert 'Uso:' in command('shell missing', 'x64> ')
        print('shell64 QEMU: switch, rescue, validation and syscalls OK')
    finally:
        vm.terminate()
        try: vm.wait(timeout=5)
        except subprocess.TimeoutExpired: vm.kill(); vm.wait()
