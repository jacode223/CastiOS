#!/usr/bin/env python3
"""Genera e integra un driver NASM estatico. Ejemplo: python3 tools/new_driver.py hello"""
from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parent.parent
if len(sys.argv) != 2 or not re.fullmatch(r'[a-z][a-z0-9_]{0,14}', sys.argv[1]):
    raise SystemExit('Uso: python3 tools/new_driver.py NOMBRE (minusculas, cifras, _, maximo 15)')
name = sys.argv[1]
folder = root / 'src/drivers'
destination = folder / (name+'.asm')
kernel = root / 'src/kernel.asm'
manifest = folder / 'manifest.inc'
if destination.exists():
    raise SystemExit('El archivo ya existe; no se ha modificado nada.')
original_kernel = kernel.read_text()
original_manifest = manifest.read_text()
entries=[]
for line in original_manifest.splitlines():
    code=line.split(';',1)[0].strip()
    if code.startswith('dd '):
        entries.extend(part.strip() for part in code[3:].split(','))
if not entries or entries[-1]!='0':
    raise SystemExit('Manifiesto invalido: falta terminador dd 0.')
if len(entries)-1 >= 16:
    raise SystemExit('Revisa el limite de 16 drivers antes de agregar otro.')
for marker, text in [('; EXTRA_DRIVER_INCLUDES', original_kernel), ('; EXTRA_DRIVERS', original_manifest)]:
    if text.count(marker) != 1:
        raise SystemExit('No se encontro un marcador unico: '+marker)
source = (folder/'template.asm.txt').read_text().replace('@NAME@',name)
new_kernel = original_kernel.replace('; EXTRA_DRIVER_INCLUDES',f'%include "src/drivers/{name}.asm"\n; EXTRA_DRIVER_INCLUDES')
new_manifest = original_manifest.replace('; EXTRA_DRIVERS',f'    dd {name}_driver\n; EXTRA_DRIVERS')
try:
    with destination.open('x') as output:
        output.write(source)
    kernel.write_text(new_kernel)
    manifest.write_text(new_manifest)
except BaseException:
    kernel.write_text(original_kernel)
    manifest.write_text(original_manifest)
    # El archivo generado queda disponible para inspeccionar si hubo error.
    raise
print(f'Creado: src/drivers/{name}.asm. Compila con bash build.sh.')
print(f'Prueba: drivers / drvinfo {name} / drvread {name}')
