"""CastiPS 0.1: offline integration checks (assembler + ABI layout).

These checks deliberately do not claim a QEMU boot. For real IRQ/iret/CR3
execution use `make test-castips-vm` after building the ISO.
"""
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / 'src/x64/kernel.asm').read_text()
proc = (ROOT / 'src/x64/castips.asm').read_text()
constants = (ROOT / 'src/x64/castips_defs.inc').read_text()
user = (ROOT / 'src/x64/user.asm').read_text()
scheduler = (ROOT / 'src/x64/scheduler.asm').read_text()

for needle in ("%include \"src/x64/castips.asm\"", "call cps_init", "call cps_ps", "call cps_reap", "pidtest_cmd"):
    assert needle in source, needle
for needle in ('%define CPS_MAX 32', '%define CPS_ENTRY_SIZE 64', '%define CPS_USER_BASE_SLOT 2',
               '%define CPS_ZOMBIE 4'):
    assert needle in constants, needle
for needle in ('cps_register:', 'cps_finish_current:', 'cps_tick_current:',
               'cps_resume_shell:', 'cps_ps:', 'cps_reap:', 'inc dword [cps_next_pid]'):
    assert needle in proc, needle
for needle in ('cmp rax, 50', 'syscall64_table:', 'dq syscall80.getpid, cps_sys_yield', 'app_pidtest:'):
    assert needle in user, needle
for needle in ('call cps_tick_current', 'call cps_finish_current', 'cps_sys_yield:',
               'mov [task_rsp+rbx*8], rsp', 'call task_activate'):
    assert needle in scheduler, needle

nasm = os.environ.get('NASM', 'nasm')
resolved = shutil.which(nasm)
if resolved:
    sample = ROOT / 'build/x64/sample_shell.bin'
    sample.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([resolved, '-f', 'bin', str(ROOT/'examples/shell64/shell.asm'), '-o', str(sample)], check=True)
    with tempfile.TemporaryDirectory() as temp:
        out = Path(temp) / 'kernel64.bin'
        subprocess.run([resolved, '-f', 'bin', '-Wall', '-Werror', '-w-implicit-abs-deprecated',
                        '-w-reloc-abs-word', '-w-reloc-abs-dword',
                        '-w-reloc-abs-qword',
                        'src/x64/kernel.asm', '-o', str(out)],
                       cwd=ROOT, check=True)
        binary = out.read_bytes()
        assert struct.unpack_from('<I', binary, 0)[0] == 0x1BADB002
        assert len(binary) < 4*1024*1024
        for literal in (b'CastiPS 0.1', b'pidtest64\x00', b'PID=\x00',
                        b'ZOMBIE\x00', b'multi-root\x00', b'multi-alice\x00'):
            assert literal in binary, literal
    print('CastiPS 0.1: verificacion de fuente + ensamblado NASM OK.')
else:
    print('CastiPS 0.1: verificacion estatica OK. NASM no encontrado, no se verifico el ensamblado.')
