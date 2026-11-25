"""HSFS5: extents, validacion estricta y migracion ASFS1/2/3."""
import re
import struct
from pathlib import Path

COUNT, RECORD, HEADER, LIMIT = 480, 8192, 64, 8000
SIZE = 512 + COUNT*RECORD
ROOT = 0xffffffff

def blank():
    image=bytearray(SIZE)
    image[:4]=b'HSF5'
    struct.pack_into('<III',image,4,5,COUNT,RECORD)
    return image

def put(image,index,name,body=b'',parent=ROOT,kind=1):
    encoded=name.encode('ascii')
    if not re.fullmatch(rb'[A-Za-z0-9_.-]{1,31}',encoded) or name in ('.','..'):raise ValueError('Nombre invalido')
    if kind not in (1,2,3) or (kind==2 and body) or len(body)>COUNT*LIMIT:raise ValueError('Tipo o longitud invalida')
    if not 0<=index<COUNT:raise ValueError('Indice invalido')
    old=list(chain(image,index)) if image[512+index*RECORD] else [index]
    available=old+[i for i in range(COUNT) if i not in old and not image[512+i*RECORD]]
    needed=max(1,(len(body)+LIMIT-1)//LIMIT)
    if needed>len(available):raise ValueError('HSFS5 sin bloques libres')
    for i in old:image[512+i*RECORD:512+(i+1)*RECORD]=bytes(RECORD)
    blocks=available[:needed]
    for ordinal,i in enumerate(blocks):
        offset=512+i*RECORD;image[offset:offset+RECORD]=bytes(RECORD)
        part=body[ordinal*LIMIT:(ordinal+1)*LIMIT]
        if ordinal==0:
            image[offset:offset+len(encoded)]=encoded
            struct.pack_into('<III',image,offset+32,parent,kind,len(body))
        else:
            image[offset]=255;struct.pack_into('<III',image,offset+32,index,4,len(part))
        struct.pack_into('<I',image,offset+44,blocks[ordinal+1]+1 if ordinal+1<needed else 0)
        image[offset+HEADER:offset+HEADER+len(part)]=part

def chain(image,index):
    seen=set()
    while True:
        if index in seen or not 0<=index<COUNT:raise ValueError('Cadena invalida')
        seen.add(index);yield index
        nxt=struct.unpack_from('<I',image,512+index*RECORD+44)[0]
        if not nxt:return
        index=nxt-1

def body(image,index):
    length=struct.unpack_from('<I',image,512+index*RECORD+40)[0];result=bytearray()
    for i in chain(image,index):
        take=min(length,LIMIT);offset=512+i*RECORD+HEADER
        result.extend(image[offset:offset+take]);length-=take
    if length:raise ValueError('Archivo truncado')
    return bytes(result)

def seal(image):
    struct.pack_into('<I',image,16,sum(image[512:SIZE]))
    return image

def fresh():
    image=blank()
    put(image,0,'readme.txt',b'CastiOS 0.8. NASM real: nasm -f bin demo.asm -o demo.bin\nHSFS5: extents. Usa -m 256 para NASM.\n')
    put(image,1,'demo.asm',b'bits 32\nmov eax, 40\nadd eax, 2\nret\n')
    put(image,2,'docs',kind=2)
    put(image,3,'nota.txt',b'Carpetas y extents persistentes en HSFS5.\n',parent=2)
    put(image,4,'app.asm',b"bits 32\n%define ANSWER 42\ndb 'AX05'\ndd code_end-code\ncode:\nmov eax, ANSWER\nret\ncode_end:\n")
    guides=sorted((Path(__file__).resolve().parent.parent/'docs/on_disk').glob('*.TXT'))
    for i,p in enumerate(guides,5):
        put(image,i,p.name,p.read_bytes(),parent=2)
    put(image,25,'lib',kind=2)
    put(image,26,'io.inc',(Path(__file__).resolve().parent.parent/'lib/io.inc').read_bytes(),parent=25)
    put(image,27,'math.inc',(Path(__file__).resolve().parent.parent/'lib/math.inc').read_bytes(),parent=25)
    put(image,28,'math.cas',(Path(__file__).resolve().parent.parent/'lib/math.cas').read_bytes(),parent=25)
    put(image,29,'util.cas',(Path(__file__).resolve().parent.parent/'lib/util.cas').read_bytes(),parent=25)
    put(image,31,'desk.cas',(Path(__file__).resolve().parent.parent/'lib/desk.cas').read_bytes(),parent=25)
    put(image,30,'desk.cas',(Path(__file__).resolve().parent.parent/'examples/castic/desktop.cas').read_bytes())
    return seal(image)

def seed_guides(image):
    """Add missing on-disk guides without replacing user files."""
    image=validate(image)
    entries={}
    for i in range(COUNT):
        off=512+i*RECORD
        if image[off] and struct.unpack_from('<I',image,off+36)[0]!=4:
            entries[(struct.unpack_from('<I',image,off+32)[0],bytes(image[off:off+32]).split(b'\0',1)[0])]=i
    folder=entries.get((ROOT,b'docs'))
    if folder is None:
        folder=next((i for i in range(COUNT) if not image[512+i*RECORD]),None)
        if folder is None:raise ValueError('HSFS sin espacio para /docs')
        put(image,folder,'docs',kind=2)
    elif struct.unpack_from('<I',image,512+folder*RECORD+36)[0]!=2:
        raise ValueError('/docs existe y no es una carpeta')
    changed=False
    for path in sorted((Path(__file__).resolve().parent.parent/'docs/on_disk').glob('*.TXT')):
        if (folder,path.name.encode('ascii')) in entries:continue
        i=next((i for i in range(COUNT) if not image[512+i*RECORD]),None)
        if i is None:raise ValueError('HSFS sin espacio para guias')
        put(image,i,path.name,path.read_bytes(),parent=folder);changed=True
    if changed:
        struct.pack_into('<I',image,20,(struct.unpack_from('<I',image,20)[0]+1)&0xffffffff)
    return validate(seal(image))

def validate(data):
    if len(data)<SIZE or data[:4]!=b'HSF5' or struct.unpack_from('<III',data,4)!=(5,COUNT,RECORD):
        raise ValueError('Cabecera HSFS5 incompatible')
    if struct.unpack_from('<I',data,16)[0]!=sum(data[512:SIZE]):
        raise ValueError('Checksum HSFS5 incorrecto')
    entries={}; names=set();visited=set();large_extents=[]
    for i in range(COUNT):
        record=data[512+i*RECORD:512+(i+1)*RECORD]
        if not record[0]:continue
        parent,kind,length=struct.unpack_from('<III',record,32)
        if kind==4:
            if record[0]!=255 or parent>=COUNT or length>LIMIT:raise ValueError('Extent invalido')
            continue
        if record[31]:raise ValueError('Nombre sin terminador')
        name=bytes(record[:32]).split(b'\0',1)[0]
        if not re.fullmatch(rb'[A-Za-z0-9_.-]{1,31}',name) or name in (b'.',b'..'):
            raise ValueError('Nombre invalido')
        parent,kind,length=struct.unpack_from('<III',record,32)
        if kind==5:
            start,sectors=struct.unpack_from('<II',record,48)
            if not name or record[31] or length==0 or length>104857600 or start<16384 or sectors!=(length+511)//512 or start+sectors>0x10000000 or struct.unpack_from('<I',record,44)[0]:raise ValueError('Archivo grande invalido')
            if (parent,name) in names:raise ValueError('Nombre duplicado')
            names.add((parent,name));entries[i]=(parent,kind);visited.add(i)
            for lo,hi in large_extents:
                if start<hi and lo<start+sectors:raise ValueError('Datos grandes solapados')
            large_extents.append((start,start+sectors))
            continue
        if kind not in (1,2,3) or length>COUNT*LIMIT or (kind==2 and length):
            raise ValueError('Registro invalido')
        if (parent,name) in names:raise ValueError('Nombre duplicado')
        names.add((parent,name));entries[i]=(parent,kind)
        left=length
        for ordinal,block in enumerate(chain(data,i)):
            if block in visited:raise ValueError('Extent compartido')
            visited.add(block);r=data[512+block*RECORD:512+(block+1)*RECORD];used=min(left,LIMIT)
            if ordinal and (r[0]!=255 or struct.unpack_from('<III',r,32)!=(i,4,used)):raise ValueError('Propietario o longitud invalida')
            if kind==1 and r[HEADER+used]:raise ValueError('Texto sin terminador')
            if bool(struct.unpack_from('<I',r,44)[0])!=(left>LIMIT):raise ValueError('Cadena truncada o larga')
            left-=used
    for i in range(COUNT):
        if data[512+i*RECORD] and i not in visited:raise ValueError('Extent huerfano')
    for index,(parent,_) in entries.items():
        seen={index}
        while parent!=ROOT:
            if parent in seen or parent not in entries or entries[parent][1]!=2:
                raise ValueError('Padre o ciclo invalido')
            seen.add(parent);parent=entries[parent][0]
    return bytearray(data[:SIZE])

def extract_or_migrate(data):
    for base in (0, 16*1024*1024):
        for offset in (base, base+8192*512):
            try:
                return validate(data[offset:offset+SIZE])
            except ValueError:
                pass
    import fs_legacy
    old=fs_legacy.extract_or_migrate(data)
    result=blank()
    result[512:512+fs_legacy.COUNT*RECORD]=old[512:fs_legacy.SIZE]
    result[20:24]=old[20:24]
    return validate(seal(result))
