from pathlib import Path
import os,subprocess,shutil
from fs_format import fresh
root=Path(__file__).resolve().parent.parent
b=root/'build'; d=Path(os.environ.get('GRUB_DIR','/usr/lib/grub/i386-pc'))
video=os.environ.get('CASTIOS_VIDEO','1024x768x32')
if video not in ('text','1024x768x32'):
    raise SystemExit('CASTIOS_VIDEO no admitido')
def iso(folder,output,live=False):
    boot=folder/'boot/grub';boot.mkdir(parents=True,exist_ok=True)
    kernel=(b/'kernel.bin').read_bytes()
    assert len(kernel)<=131072
    (folder/'boot/kernel.bin').write_bytes(kernel.ljust(131072,b'\0'))
    if not live:
        (folder/'boot/NEXT.BIN').write_bytes(kernel.ljust(131072,b'\0'))
        slot=b'set default=0\n# CASTIOS-SLOT-V1 R\n'
        (folder/'boot/SLOT.CFG').write_bytes(slot.ljust(2047,b' ')+b'\n')
    shutil.copyfile(b/'nasm32',folder/'boot/nasm32')
    shutil.copyfile(b/'zzcastic.bin',folder/'boot/zzcastic.bin')
    (folder/'boot/zzspeed.bin').unlink(missing_ok=True)
    (folder/'boot/drive.cfg').write_text('set asmdisk=hda\n')
    config=b/('live.cfg' if live else 'disk.cfg')
    if live:
        shutil.copyfile(b/'setup.bin',folder/'boot/setup.bin')
        config.write_text('search --file --set=root /boot/installer.iso\n'+f'set gfxpayload={video}\nsource /boot/drive.cfg\nmultiboot /boot/kernel.bin disk=$asmdisk\nmodule /boot/installer.iso\nmodule /boot/nasm32 nasm\nmodule /boot/zzcastic.bin castic\nmodule /boot/setup.bin setup\nboot\n')
    else:
        (boot/'grub.cfg').write_text(f'set gfxpayload={video}\nsource /boot/drive.cfg\nset default=0\nsource /boot/SLOT.CFG\nset timeout=5\nmenuentry "CastiOS estable" {{\nmultiboot /boot/kernel.bin disk=$asmdisk\nmodule /boot/nasm32 nasm\nmodule /boot/zzcastic.bin castic\n}}\nmenuentry "CastiOS nuevo" {{\nmultiboot /boot/NEXT.BIN disk=$asmdisk trial=1\nmodule /boot/nasm32 nasm\nmodule /boot/zzcastic.bin castic\n}}\n')
        config.write_text('normal\n')
    subprocess.run(['grub-mkimage','-d',str(d),'-O','i386-pc-eltorito','-p','/boot/grub','-c',str(config),'-o',str(boot/'eltorito.img'),'biosdisk','iso9660','multiboot','normal','search','search_fs_file','configfile','all_video'],check=True)
    subprocess.run(['xorriso','-as','mkisofs','-quiet','-R','-b','boot/grub/eltorito.img','-no-emul-boot','-boot-load-size','4','-boot-info-table','--grub2-boot-info','--grub2-mbr',str(d/'boot_hybrid.img'),'-o',str(output),str(folder)],check=True)
    if not live:
        report=subprocess.run(['xorriso','-indev',str(output),'-find','/boot','-exec','report_lba','--'],capture_output=True,text=True,check=True).stdout
        for name,lba,blocks in (('NEXT.BIN',110,64),('SLOT.CFG',174,1),('kernel.bin',177,64)):
            expected=f'{lba:>9} , {blocks:>8} ,'
            assert any(expected in row and "'/boot/"+name+"'" in row for row in report.splitlines()), f'ISO layout changed for {name}; update kupdate.asm before releasing'
iso(b/'grub-disk',b/'installer.iso')
live=b/'grub-live';(live/'boot').mkdir(parents=True,exist_ok=True)
shutil.copyfile(b/'installer.iso',live/'boot/installer.iso')
iso(live,b/'CastiOS.iso',True)
disk=b/'asfs4.img'
if not disk.exists():
    data=bytearray(32*1024*1024);v=fresh();data[:len(v)]=v;data[8192*512:8192*512+len(v)]=v
    disk.write_bytes(data)
