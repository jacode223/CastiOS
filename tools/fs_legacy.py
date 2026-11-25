"""ASFS4: extents, validacion estricta y migracion ASFS1/2/3."""
import re
import struct

COUNT, RECORD, HEADER, LIMIT = 256, 8192, 64, 8000
SIZE = 512 + COUNT*RECORD
ROOT = 0xffffffff

def blank():
    image=bytearray(SIZE)
    image[:4]=b'ASF4'
    struct.pack_into('<III',image,4,4,COUNT,RECORD)
    return image

def put(image,index,name,body=b'',parent=ROOT,kind=1):
    encoded=name.encode('ascii')
    if not re.fullmatch(rb'[A-Za-z0-9_.-]{1,31}',encoded) or name in ('.','..'):raise ValueError('Nombre invalido')
    if kind not in (1,2,3) or (kind==2 and body) or len(body)>COUNT*LIMIT:raise ValueError('Tipo o longitud invalida')
    if not 0<=index<COUNT:raise ValueError('Indice invalido')
    old=list(chain(image,index)) if image[512+index*RECORD] else [index]
    available=old+[i for i in range(COUNT) if i not in old and not image[512+i*RECORD]]
    needed=max(1,(len(body)+LIMIT-1)//LIMIT)
    if needed>len(available):raise ValueError('ASFS4 sin bloques libres')
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
    put(image,0,'readme.txt',b'ASM-OS 0.8. NASM real: nasm -f bin demo.asm -o demo.bin\nASFS4: extents. Usa -m 256 para NASM.\n')
    put(image,1,'demo.asm',b'bits 32\nmov eax, 40\nadd eax, 2\nret\n')
    put(image,2,'docs',kind=2)
    put(image,3,'nota.txt',b'Carpetas y extents persistentes en ASFS4.\n',parent=2)
    put(image,4,'app.asm',b"bits 32\n%define ANSWER 42\ndb 'AX05'\ndd code_end-code\ncode:\nmov eax, ANSWER\nret\ncode_end:\n")
    return seal(image)

def validate(data):
    if len(data)<SIZE or data[:4]!=b'ASF4' or struct.unpack_from('<III',data,4)!=(4,COUNT,RECORD):
        raise ValueError('Cabecera ASFS4 incompatible')
    if struct.unpack_from('<I',data,16)[0]!=sum(data[512:SIZE]):
        raise ValueError('Checksum ASFS4 incorrecto')
    entries={}; names=set();visited=set()
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
    candidates=[]
    for base in (0,16*1024*1024):
        for offset in (base,base+8192*512):
            part=data[offset:offset+SIZE]
            try:
                if part[:4]==b'ASF4':v=validate(part)
                elif part[:4]==b'ASF3':
                    if len(part)<SIZE or struct.unpack_from('<III',part,4)!=(3,COUNT,RECORD):continue
                    if any(struct.unpack_from('<I',part,512+i*RECORD+40)[0]>LIMIT or struct.unpack_from('<I',part,512+i*RECORD+44)[0] for i in range(COUNT) if part[512+i*RECORD]):continue
                    v=bytearray(part);v[:4]=b'ASF4';struct.pack_into('<I',v,4,4);validate(v)
                else:continue
                candidates.append(v)
            except (ValueError,struct.error):pass
    if candidates:return max(candidates,key=lambda v:struct.unpack_from('<I',v,20)[0])
    if data[16*1024*1024:16*1024*1024+4] in (b'ASF2',b'ASF3'):data=data[16*1024*1024:]
    if data[384:392] in (b'ASM04HD\0',b'ASM05HD\0'):data=data[128*512:]
    if data[:4]==b'ASF3':
        valid=[]
        for offset in (0,8192*512):
            try:valid.append(validate(data[offset:]))
            except ValueError:pass
        if not valid:raise ValueError('Ambas copias ASFS3 son invalidas')
        return max(valid,key=lambda v:struct.unpack_from('<I',v,20)[0])
    if data[:4]==b'ASF2':
        if len(data)<262656 or struct.unpack_from('<III',data,4)!=(2,64,4096):
            raise ValueError('ASFS2 incompatible')
        if struct.unpack_from('<I',data,16)[0]!=sum(data[512:262656]):
            raise ValueError('ASFS2 corrupto')
        result=blank()
        for i in range(64):
            record=data[512+i*4096:512+(i+1)*4096]
            if not record[0]:continue
            parent,kind,length=struct.unpack_from('<III',record,32)
            if record[31] or length>4000 or kind not in (1,2,3):
                raise ValueError('Registro ASFS2 invalido')
            put(result,i,record[:32].split(b'\0',1)[0].decode('ascii'),record[64:64+length],parent,kind)
        return validate(seal(result))
    if data[:4]!=b'ASFS' or len(data)<33280 or struct.unpack_from('<III',data,4)!=(1,32,1024):
        raise ValueError('No es ASFS1 ni ASFS3')
    if struct.unpack_from('<I',data,16)[0]!=sum(data[512:33280]):raise ValueError('ASFS1 corrupto')
    image=blank()
    for i in range(32):
        record=data[512+i*1024:512+(i+1)*1024]
        if not record[0]:continue
        name=record[:16].split(b'\0',1)[0].decode('ascii')
        length=struct.unpack_from('<I',record,16)[0]
        if record[15] or length>1000 or record[20+length]:raise ValueError('Registro ASFS1 invalido')
        put(image,i,name,record[20:20+length])
    return validate(seal(image))
