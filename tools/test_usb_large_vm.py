"""Optional integration: 64 GB sparse FAT32 drive, no real disk touched.
Run after make i386; needs QEMU, dosfstools and mtools. Not run in build environment."""
import os
import shlex
import subprocess
import tempfile
from pathlib import Path
from vm_harness import VM, ROOT

controllers = [('EHCI', 'usb-ehci'), ('UHCI', 'piix3-usb-uhci'), ('xHCI', 'qemu-xhci')]
with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    image = root / 'fat64gb.img'
    with image.open('wb') as f:
        f.truncate(64_000_000_000)
    subprocess.run(['mkfs.fat', '-F', '32', '-s', '64', str(image)], check=True)
    text = root / 'HELLO.TXT'
    text.write_text('CastiUSB FAT32 64 GB\n')
    subprocess.run(['mcopy', '-i', str(image), str(text), '::/'], check=True)
    old = os.environ.get('QEMU_EXTRA_ARGS', '')
    try:
        for label, device in controllers:
            work = root / label
            work.mkdir()
            args = ['-device', f'{device},id=usbh', '-drive',
                    f'file={image},format=raw,if=none,id=stick,snapshot=on',
                    '-device', 'usb-storage,drive=stick,bus=usbh.0,port=1,id=stickdev']
            os.environ['QEMU_EXTRA_ARGS'] = old + ' ' + shlex.join(args)
            v = VM(work, memory=128)
            try:
                v.cmd('castctl usbscan', 'USB total: 1 disco(s).')
                info = v.cmd('castctl usbinfo', 'listo, solo lectura')
                assert label in info and '125000000' in info, info
                v.cmd('mount usb0 /mnt/usb', 'Montado FAT32')
                v.cmd('cat /mnt/usb/HELLO.TXT', 'CastiUSB FAT32 64 GB')
                v.cmd('castctl usbscan', 'USB total: 1 disco(s).')
                v.cmd('mount usb0 /mnt/usb', 'Montado FAT32')
                v.cmd('cat /mnt/usb/HELLO.TXT', 'CastiUSB FAT32 64 GB')
                print(f'OK: {label}, FAT32 64 GB, rescan y lectura.')
            finally:
                v.close()
    finally:
        os.environ['QEMU_EXTRA_ARGS'] = old
