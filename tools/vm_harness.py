"""Pruebas de ISO y ASFS con teclado real PS/2 emulado mediante QMP."""
import json
import os
from pathlib import Path
import re
import select
import shlex
import shutil
import struct
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parent.parent

class VM:
    def __init__(self, work, disk=None, boot_disk=False, serial=False, slave=None, boot_slave=False, disk_positions=None, prompt='CastiOS> ', memory=None):
        self.prompt = prompt
        self.log = work / 'debug.log'
        self.log.write_bytes(b'')
        self.err = (work / 'qemu.err').open('w')
        args = [os.environ.get('QEMU', 'qemu-system-i386'), '-m', str(memory or 32), '-accel', 'tcg',
                '-display', 'none',
                '-serial', 'file:'+str(work/'serial.log') if serial else 'none', '-monitor', 'none', '-nic', 'none', '-qmp', 'stdio',
                '-debugcon', f'file:{self.log}']
        if boot_disk: args += ['-boot','c']
        else:
            args += ['-boot','d']
            slot = 2 if disk_positions is None else next(i for i in (2,3,1,0) if i not in disk_positions)
            args += ['-drive', f"file={ROOT/'build/CastiOS.iso'},format=raw,if=none,media=cdrom,id=bootcd",
                     '-device', f'ide-cd,drive=bootcd,bus=ide.{slot//2},unit={slot%2},bootindex=0']
        if disk_positions is not None:
            for slot, path in disk_positions.items():
                args += ['-drive', f'file={path},format=raw,if=none,id=slot{slot}',
                         '-device', f'ide-hd,drive=slot{slot},bus=ide.{slot//2},unit={slot%2},bootindex={slot+1}']
        if disk:
            args += ['-drive', f'file={disk},format=raw,if=none,id=master', '-device',
                     'ide-hd,drive=master,bus=ide.0,unit=0,bootindex='+('2' if boot_slave else '1')]
        if slave:
            args += ['-drive', f'file={slave},format=raw,if=none,id=slave', '-device',
                     'ide-hd,drive=slave,bus=ide.0,unit=1,bootindex='+('1' if boot_slave else '2')]
        extra=shlex.split(os.environ.get('QEMU_EXTRA_ARGS',''))
        if memory is not None: extra += ['-m', str(memory)]
        self.p = subprocess.Popen(args + extra,
                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=self.err, bufsize=0)
        try:
            self.read()
            self.qmp('qmp_capabilities')
            self.wait('asm:/ > ')
        except Exception:
            self.close()
            raise
    def read(self):
        assert select.select([self.p.stdout], [], [], int(os.environ.get("VM_READ_TIMEOUT", "15")))[0], 'QMP timeout'
        line = self.p.stdout.readline()
        assert line, 'QEMU cerrado'
        return json.loads(line)
    def qmp(self, execute, arguments=None):
        message = {'execute':execute}
        if arguments: message['arguments'] = arguments
        self.p.stdin.write(json.dumps(message).encode()+b'\n')
        while True:
            value = self.read()
            assert 'error' not in value, value
            if 'return' in value: return value['return']
    def out(self): return self.log.read_bytes().decode('ascii', errors='replace')
    def wait(self, text, offset=0):
        text = text.replace('asm:/ > ', self.prompt)
        deadline = time.monotonic()+int(os.environ.get("VM_WAIT_TIMEOUT", "15"))
        while time.monotonic()<deadline:
            if text in self.out()[offset:]: return self.out()[offset:]
            time.sleep(.02)
        raise AssertionError((text,self.out()[-3000:]))
    def key(self, name):
        self.qmp('human-monitor-command', {'command-line':f'sendkey {name} 10'})
        time.sleep(.024)
    def type(self, text):
        mapping = {' ':'spc','.':'dot','-':'minus','+':'shift-equal','_':'shift-minus','/':'slash',',':'comma',';':'semicolon',':':'shift-semicolon','\n':'ret'}
        for c in text:
            self.key('shift-'+c.lower() if c.isupper() else mapping.get(c,c))
    def cmd(self, text, expected=None):
        start=len(self.out())
        self.type(text); self.key('ret')
        result=self.wait('asm:/ > ',start)
        if expected is not None: assert expected in result, (text,result)
        return result
    def edit(self, name, lines, save=True, command='edit'):
        offset=len(self.out())
        self.type(command+' '+name); self.key('ret'); self.wait('edit> ',offset)
        for line in lines:
            offset=len(self.out())
            self.type(line); self.key('ret'); self.wait('edit> ',offset)
        offset=len(self.out())
        self.type('.save' if save else '.cancel'); self.key('ret')
        self.wait('asm:/ > ',offset)
    def close(self):
        self.p.terminate()
        try: self.p.wait(timeout=5)
        except subprocess.TimeoutExpired: self.p.kill(); self.p.wait()
        self.err.close()
