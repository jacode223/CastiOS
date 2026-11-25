#!/usr/bin/env python3
"""Create a new bootable BIOS x64 IDE disk image with an HSFS6 volume.

Creates only a new regular file. Existing images and block devices are refused.
"""
import argparse
import os
from pathlib import Path
from hsfs6 import SECTOR, TABLE_LBA, HEADER_LBA, TABLE_SIZE, header

ROOT=Path(__file__).resolve().parent.parent
BASE=16*1024*1024

def create(target,size):
    iso=(ROOT/'dist/CastiOS-x64-preview.iso').read_bytes()
    if len(iso)>BASE:raise ValueError('ISO supera el espacio reservado')
    if size<BASE+1024*1024 or size%SECTOR:raise ValueError('Disco demasiado pequeno')
    sectors=(size-BASE)//SECTOR
    table=bytes(TABLE_SIZE)
    with target.open('xb') as f:
        f.truncate(size)
        f.seek(0);f.write(iso)
        for i in (0,1):
            f.seek(BASE+TABLE_LBA[i]*SECTOR);f.write(table)
            f.seek(BASE+HEADER_LBA[i]*SECTOR);f.write(header(0,sectors,table,i))
        f.flush();os.fsync(f.fileno())
    print('Imagen BIOS creada:',target)

if __name__=='__main__':
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('imagen',type=Path)
    ap.add_argument('--size-mib',type=int,default=128)
    args=ap.parse_args()
    create(args.imagen,args.size_mib*1024*1024)
