"""Create a NEW FAT32 demo file, optionally copying one user-provided TTF.
Requires mkfs.fat and mtools on the host. Never operates on an existing file.
"""
import argparse,subprocess,tempfile
from pathlib import Path
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('output',type=Path)
parser.add_argument('--font',type=Path)
args=parser.parse_args()
out=args.output.absolute()
if out.exists() or out.is_symlink() or out.resolve().is_relative_to('/dev'):
 raise SystemExit('Destino existente o dispositivo: no se modifica.')
if args.font and (not args.font.is_file() or args.font.stat().st_size>1048576):
 raise SystemExit('La TTF debe existir y ocupar como maximo 1 MiB.')
if not out.parent.is_dir():raise SystemExit('La carpeta de destino debe existir.')
with out.open('xb') as f:f.truncate(64*1024*1024)
subprocess.run(['mkfs.fat','-F','32',str(out)],check=True)
with tempfile.TemporaryDirectory() as t:
 p=Path(t)/'README.TXT'
 p.write_text('FAT32 demo para CastiOS.\nmount usb0 /mnt/usb\nls /mnt/usb\nfont /mnt/usb/FONT.TTF\n')
 subprocess.run(['mcopy','-i',str(out),str(p),'::/README.TXT'],check=True)
if args.font:
 subprocess.run(['mcopy','-i',str(out),str(args.font),'::/FONT.TTF'],check=True)
print('Imagen nueva FAT32 (sin tabla de particiones):',out)
