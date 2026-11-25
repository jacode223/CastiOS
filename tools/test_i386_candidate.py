"""Targeted i386 regression suite; does not certify production stability."""
from pathlib import Path
import subprocess, sys
root=Path(__file__).resolve().parent.parent
checks=('test_public_install_i386.py','test_hsfs_commit.py','test_demand_isolation.py','test_syscalls.py',
        'test_castic_i386_vm.py','test_castic_syscalls_i386.py','test_pe32.py','test_usb_mouse_i386.py')
for check in checks:
    print(f'\n== {check} ==',flush=True)
    subprocess.run([sys.executable,str(root/'tools'/check)],cwd=root,check=True)
print('\nCandidate i386 regression suite: OK (not a stability certification).')
