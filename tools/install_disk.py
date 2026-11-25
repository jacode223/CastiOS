"""Crea un disco arrancable nuevo e importa ASFS1/ASFS2 sin tocar el origen."""
from pathlib import Path
import argparse
from fs_format import extract_or_migrate,seed_guides,COUNT,RECORD
import struct
root=Path(__file__).resolve().parent.parent
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('output',type=Path)
parser.add_argument('--data',type=Path,default=root/'build/asfs4.img')
parser.add_argument('--target',choices=['hda','hdb','hdc','hdd'],default='hda')
args=parser.parse_args()
target=args.output.absolute()
if target.exists() or target.is_symlink() or target.resolve().is_relative_to('/dev'):
    raise SystemExit('Destino existente o dispositivo: no se modifica.')
try:fs=seed_guides(extract_or_migrate(args.data.read_bytes()))
except (ValueError,UnicodeError) as error:raise SystemExit(str(error))
if any(fs[512+i*RECORD] and struct.unpack_from('<I',fs,512+i*RECORD+36)[0]==5 for i in range(COUNT)):
    raise SystemExit('La imagen contiene archivos HSFS grandes; copia el disco completo, no solo los metadatos.')
boot=(root/'build/installer.iso').read_bytes()
boot=boot.replace(b'set asmdisk=hda\n',('set asmdisk='+args.target+'\n').encode())
assert len(boot)<16*1024*1024
image=bytearray(32*1024*1024)
image[:len(boot)]=boot
image[16*1024*1024:16*1024*1024+len(fs)]=fs
image[16*1024*1024+8192*512:16*1024*1024+8192*512+len(fs)]=fs
with target.open('xb') as output:output.write(image)
print('Disco nuevo listo:',target)
