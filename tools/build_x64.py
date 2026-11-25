"""Build the separate BIOS/GRUB x86-64 bootstrap ISO; leave i386 intact."""
from pathlib import Path
import os
import subprocess

root=Path(__file__).resolve().parent.parent
(root/'dist').mkdir(exist_ok=True)
grub=Path(os.environ.get('GRUB_DIR','/usr/lib/grub/i386-pc'))
out=root/'build/x64'
boot=out/'iso/boot/grub'
boot.mkdir(parents=True,exist_ok=True)
subprocess.run(['nasm','-f','bin',str(root/'examples/shell64/shell.asm'), '-o',str(out/'sample_shell.bin')],check=True)
subprocess.run(['nasm','-f','bin','-Wall','-Werror','-w-implicit-abs-deprecated','-w-reloc-abs-word',
                '-w-reloc-abs-dword','-w-reloc-abs-qword',str(root/'src/x64/kernel.asm'),
                '-o',str(out/'kernel64.bin')],check=True)
subprocess.run(['grub-file','--is-x86-multiboot',str(out/'kernel64.bin')],check=True)
(out/'iso/boot/kernel64.bin').write_bytes((out/'kernel64.bin').read_bytes())
(out/'iso/boot/install.img').unlink(missing_ok=True)
(out/'config.cfg').write_text('set gfxmode=1024x768x32\nset gfxpayload=keep\nmultiboot /boot/kernel64.bin\nboot\n')
subprocess.run(['grub-mkimage','-d',str(grub),'-O','i386-pc-eltorito','-p','/boot/grub',
                '-c',str(out/'config.cfg'),'-o',str(boot/'eltorito.img'),
                'biosdisk','iso9660','multiboot','all_video'],check=True)
subprocess.run(['xorriso','-as','mkisofs','-quiet','-R','-b','boot/grub/eltorito.img',
                '-no-emul-boot','-boot-load-size','4','-boot-info-table','--grub2-boot-info',
                '--grub2-mbr',str(grub/'boot_hybrid.img'),'-o',str(out/'install-payload.iso'),
                str(out/'iso')],check=True)
(out/'iso/boot/install.img').write_bytes((out/'install-payload.iso').read_bytes())
(out/'config.cfg').write_text('set gfxmode=1024x768x32\nset gfxpayload=keep\nmultiboot /boot/kernel64.bin\nmodule /boot/install.img installer\nboot\n')
subprocess.run(['grub-mkimage','-d',str(grub),'-O','i386-pc-eltorito','-p','/boot/grub',
                '-c',str(out/'config.cfg'),'-o',str(boot/'eltorito.img'),
                'biosdisk','iso9660','multiboot','all_video'],check=True)
subprocess.run(['xorriso','-as','mkisofs','-quiet','-R','-b','boot/grub/eltorito.img',
                '-no-emul-boot','-boot-load-size','4','-boot-info-table','--grub2-boot-info',
                '--grub2-mbr',str(grub/'boot_hybrid.img'),'-o',str(root/'dist/CastiOS-x64-preview.iso'),
                str(out/'iso')],check=True)
print('ISO x64 experimental:',root/'dist/CastiOS-x64-preview.iso')
