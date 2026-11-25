"""QEMU IDE at relocated ports. Supply PCI descriptors only in a temporary build.

The i386 QEMU build's PIIX model only exposes legacy IDE. Two QEMU isa-ide
devices provide actual taskfile I/O and IDENTIFY. The temporary PCI config
fixture describes their addresses like a PCI IDE native-mode controller.
"""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from fs_format import SIZE, RECORD, body, fresh, put, seal, validate
import vm_harness

root = vm_harness.ROOT
# Device 00:1e.0, both channels native. Command blocks and control blocks
# are deliberately nonadjacent. No data or status register is mocked.
fixture = """
    push edx
    mov edx, eax
    and edx, 0xffffff00
    cmp edx, 0x8000f000
    pop edx
    jne .hardware
    and eax, 0xfc
    cmp eax, 0x20
    jae .zero
    mov eax, [.config+eax]
    ret
.zero:
    xor eax, eax
    ret
.config:
    dd 0x1234f00d, 1, 0x01018501, 0
    dd 0x281, 0x2c1, 0x2a1, 0x2e1
.hardware:
"""
with tempfile.TemporaryDirectory() as name:
    temp = Path(name)
    tree = temp/'CastiOS'
    shutil.copytree(root, tree, ignore=shutil.ignore_patterns('build','dist','.git','__pycache__'))
    (tree/'build').mkdir()
    shutil.copy(root/'build/nasm32', tree/'build/nasm32')
    pci = tree/'src/drivers/pci.asm'
    original = pci.read_text()
    assert original.count('pci_config:\n') == 1
    pci.write_text(original.replace('pci_config:\n', 'pci_config:\n'+fixture))
    subprocess.run(['make','i386'],cwd=tree,check=True)

    blank = temp/'primary.img'
    disk = temp/'secondary.img'
    for path in (blank,disk):
        with path.open('wb') as f:
            f.truncate(32*1024*1024)
    initial = hashlib.sha256(blank.read_bytes()).digest()
    fs = fresh()
    put(fs,40,'marker.txt',b'secondary slave')
    seal(fs)
    with disk.open('r+b') as f:
        f.write(fs)
        f.seek(8192*512)
        f.write(fs)
    os.environ['QEMU_EXTRA_ARGS'] = os.environ.get('QEMU_EXTRA_ARGS','') + (
        ' -device isa-ide,id=p,iobase=0x280,iobase2=0x2c2,irq=10'
        ' -device isa-ide,id=s,iobase=0x2a0,iobase2=0x2e2,irq=11'
        f' -drive file={blank},format=raw,if=none,id=d0'
        ' -device ide-hd,drive=d0,bus=p.0,unit=0'
        f' -drive file={disk},format=raw,if=none,id=d1'
        ' -device ide-hd,drive=d1,bus=s.0,unit=1')
    # The shipping ISO has no synthetic PCI descriptors and must leave the
    # same extra ATA devices untouched in the absence of reported BARs.
    vm = vm_harness.VM(temp)
    try:
        assert 'IDE PCI nativo |' not in vm.cmd('disks')
        assert 'RMFS disponible' in vm.out()
    finally:
        vm.close()
    vm_harness.ROOT = tree
    for reboot in (False,True):
        vm = vm_harness.VM(temp)
        try:
            inventory = vm.cmd('disks','1234F00D/01018501')
            assert inventory.count('IDE PCI nativo |') == 2, inventory
            vm.cmd('cat marker.txt','secondary slave')
            if reboot:
                vm.cmd('cat saved.txt','native')
            else:
                vm.cmd('castctl write saved.txt native','Guardado en disco')
        finally:
            vm.close()
    assert hashlib.sha256(blank.read_bytes()).digest() == initial
    raw = disk.read_bytes()
    fs = validate(raw[:SIZE])
    assert fs == raw[8192*512:8192*512+SIZE]
    index = next(i for i in range(480) if fs[512+i*RECORD:522+i*RECORD].startswith(b'saved.txt\0'))
    assert body(fs,index) == b'native'
print('OK: native BAR0..3, both channels, master/slave, persistent write; other disk unchanged.')
