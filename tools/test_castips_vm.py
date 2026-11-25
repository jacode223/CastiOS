"""CastiPS 0.1 QEMU integration: real CPL3, PIT, getpid, yield and ps/reap.
Requires `make x64` and qemu-system-x86_64. This test is not an offline test.
"""
import json
import os
import re
import shlex
from pathlib import Path
import select
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as tmp:
    log = Path(tmp) / 'debug.log'
    cmd = ['qemu-system-x86_64', '-m', '256', '-accel', 'tcg', '-display', 'none',
           '-serial', 'none', '-monitor', 'none', '-nic', 'none', '-no-reboot',
           '-boot', 'd', '-cdrom', str(ROOT / 'dist/CastiOS-x64-preview.iso'),
           '-qmp', 'stdio', '-debugcon', 'file:' + str(log)]
    cmd += shlex.split(os.environ.get('QEMU_EXTRA_ARGS', ''))
    vm = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, bufsize=0)

    def qmp(command, args=None):
        request = {'execute': command}
        if args:
            request['arguments'] = args
        vm.stdin.write(json.dumps(request).encode() + b'\n')
        while True:
            assert select.select([vm.stdout], [], [], 15)[0], 'QMP timeout'
            reply = json.loads(vm.stdout.readline())
            assert 'error' not in reply, reply
            if 'return' in reply:
                return reply['return']

    def command(line, timeout=25):
        data = log.read_text(errors='replace')
        old_len = len(data)
        for ch in line:
            key = {'-': 'minus'}.get(ch, ch)
            qmp('human-monitor-command', {'command-line': f'sendkey {key} 30'})
            time.sleep(.015)
        qmp('human-monitor-command', {'command-line': 'sendkey ret 30'})
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            text = log.read_text(errors='replace')[old_len:]
            if 'x64> ' in text and text.count('x64> ') >= 1 and '\n' in text:
                # Shell prints command via keyboard then prompt when complete.
                if text.count('x64> ') >= 1 and ('\nx64> ' in text or text.endswith('x64> ')):
                    return text
            time.sleep(.05)
        raise AssertionError(f'Command {line!r} timeout: {log.read_text(errors="replace")[-2000:]}')

    try:
        assert select.select([vm.stdout], [], [], 15)[0], 'QMP startup timeout'
        json.loads(vm.stdout.readline())
        qmp('qmp_capabilities')
        deadline = time.monotonic() + 20
        while 'x64> ' not in log.read_text(errors='replace'):
            assert time.monotonic() < deadline, 'VM did not boot'
            time.sleep(.05)
        out = command('ps')
        assert 'PID=1 PPID=0 UID=0 STATE=RUNNING' in out, out
        assert 'NAME=shell64' in out, out
        out = command('pidtest64')
        assert 'Proceso CPL3 terminado con EAX=0' in out, out
        out = command('ps')
        assert 'PID=2 PPID=1 UID=0 STATE=ZOMBIE' in out, out
        assert 'NAME=pidtest64 EXIT=0' in out, out
        out = command('multi64', timeout=40)
        assert 'root EAX=11 alice EAX=22' in out, out
        out = command('ps')
        assert 'NAME=multi-root EXIT=11' in out, out
        assert 'UID=1000 STATE=ZOMBIE' in out, out
        assert 'NAME=multi-alice EXIT=22' in out, out
        out = command('reap')
        assert 'CastiPS procesos recogidos: 2' in out, out
        out = command('ps')
        assert 'NAME=multi-root' not in out and 'NAME=multi-alice' not in out, out
        assert 'NAME=shell64' in out, out
        out = command('syscheck')
        assert 'Proceso CPL3 terminado con EAX=0' in out, out
    finally:
        vm.terminate()
        try:
            vm.wait(timeout=5)
        except subprocess.TimeoutExpired:
            vm.kill()
            vm.wait()
print('CastiPS 0.1 QEMU: getpid, yield, scheduler, ps y reap OK')
