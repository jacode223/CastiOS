"""Importa/exporta archivos ASFS4. Trabaja con la VM apagada y crea imagen nueva."""
import argparse,struct
from pathlib import Path,PurePosixPath
from fs_format import extract_or_migrate,validate,put,body,seal,ROOT,RECORD,SIZE

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('image',type=Path)
s=p.add_subparsers(dest='command',required=True)
s.add_parser('ls');s.add_parser('check')
g=s.add_parser('get');g.add_argument('path');g.add_argument('output',type=Path)
g=s.add_parser('put');g.add_argument('local',type=Path);g.add_argument('path');g.add_argument('output_image',type=Path);g.add_argument('--binary',action='store_true')
a=p.parse_args();raw=bytearray(a.image.read_bytes());fs=extract_or_migrate(raw)
entries={}
for i in range(480):
 r=fs[512+i*RECORD:512+(i+1)*RECORD]
 if r[0] and struct.unpack_from('<I',r,36)[0]!=4:entries[i]=(r[:32].split(b'\0')[0].decode('ascii'),*struct.unpack_from('<III',r,32))
def path(i):
 name,parent,kind,length=entries[i]
 return (PurePosixPath('/') if parent==ROOT else path(parent))/name
lookup={str(path(i)):i for i in entries}
if a.command=='check':print('HSFS5 valido; bloques usados:',sum(bool(fs[512+i*RECORD]) for i in range(480)))
elif a.command=='ls':
 for i,(_,_,kind,length) in entries.items():print(str(path(i))+('/' if kind==2 else ''),length)
elif a.command=='get':
 i=lookup.get('/'+a.path.lstrip('/'))
 if i is None or entries[i][2]==2:raise SystemExit('No es un archivo.')
 with a.output.open('xb') as out:
  if entries[i][2]==5:
   offset=512+i*RECORD;start=struct.unpack_from('<I',fs,offset+48)[0]
   base=16*1024*1024 if raw[16*1024*1024:16*1024*1024+4]==b'HSF5' else 0
   pos=base+start*512;length=entries[i][3]
   if pos+length>len(raw):raise SystemExit('Datos grandes fuera de la imagen.')
   out.write(raw[pos:pos+length])
  else:out.write(body(fs,i))
else:
 if a.output_image.exists() or a.output_image.is_symlink():raise SystemExit('El destino ya existe.')
 target=PurePosixPath('/'+a.path.lstrip('/'))
 if '..' in target.parts or target==PurePosixPath('/'):raise SystemExit('Ruta invalida.')
 parent=ROOT if str(target.parent)=='/' else lookup.get(str(target.parent))
 if parent is None or (parent!=ROOT and entries[parent][2]!=2):raise SystemExit('Carpeta inexistente.')
 i=lookup.get(str(target))
 if i is not None and entries[i][2]==2:raise SystemExit('La salida es una carpeta.')
 if i is None:i=next((i for i in range(480) if not fs[512+i*RECORD]),None)
 if i is None:raise SystemExit('HSFS lleno.')
 put(fs,i,target.name,a.local.read_bytes(),parent,3 if a.binary else 1)
 struct.pack_into('<I',fs,20,(struct.unpack_from('<I',fs,20)[0]+1)&0xffffffff)
 validate(seal(fs))
 # GRUB ISO hybrid images have their storage partition at 16 MiB.
 base=16*1024*1024 if raw[:4] not in (b'ASF3',b'HSF5') and (raw[16*1024*1024:16*1024*1024+4] in (b'ASF3',b'HSF5') or raw[20*1024*1024:20*1024*1024+4] in (b'ASF3',b'HSF5')) else 0
 if len(raw)<base+8192*512+SIZE:raise SystemExit('Imagen demasiado corta para dos copias.')
 raw[base:base+SIZE]=fs;raw[base+8192*512:base+8192*512+SIZE]=fs
 with a.output_image.open('xb') as out:out.write(raw)
 print('Imagen nueva:',a.output_image)
