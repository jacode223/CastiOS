"""Empaqueta ISO, disco inicial, fuentes y resultados de validacion."""
from pathlib import Path
import hashlib
import shutil
import zipfile

root = Path(__file__).resolve().parent.parent
dist = root / 'dist'
dist.mkdir(exist_ok=True)
shutil.copyfile(root/'build/CastiOS.iso', dist/'CastiOS.iso')
shutil.copyfile(root/'build/CastiOS-hdd.img', dist/'CastiOS-hdd.img')
sums = []
for name in ('CastiOS.iso', 'asfs4.img', 'CastiOS-hdd.img', 'nasm32'):
    sums.append(hashlib.sha256((root/'build'/name).read_bytes()).hexdigest()+'  '+name)
(root/'build/SHA256SUMS').write_text('\n'.join(sums)+'\n')
with zipfile.ZipFile(dist/'CastiOS-fuentes.zip','w',zipfile.ZIP_DEFLATED,compresslevel=9) as archive:
    preview=dist/'CastiOS-x64-preview.iso'
    if preview.is_file(): archive.write(preview,Path('CastiOS/dist')/preview.name)
    for path in sorted(root.rglob('*')):
        rel=path.relative_to(root)
        if not path.is_file() or rel.parts[0]=='dist' or '__pycache__' in rel.parts or rel.parts[:2]==('build','iso'):
            continue
        if rel.parts[0]=='vendor' and rel.name not in {'NASM-3.02-source.zip','NASM-LICENSE.txt'}:
            continue
        if rel.parts[0]=='build' and (len(rel.parts)!=2 or rel.name not in {'CastiOS.iso','asfs4.img','asfs2.img','CastiOS-hdd.img','installer.iso','kernel.bin','hddboot.bin','nasm32','SHA256SUMS'}):
            continue
        archive.write(path,Path('CastiOS')/rel)
with zipfile.ZipFile(dist/'CastiOS-fuentes.zip') as archive:
    assert archive.testzip() is None
    assert archive.read('CastiOS/build/CastiOS.iso')==(dist/'CastiOS.iso').read_bytes()
    assert archive.read('CastiOS/build/asfs4.img')==(root/'build/asfs4.img').read_bytes()
    assert archive.read('CastiOS/build/CastiOS-hdd.img')==(root/'build/CastiOS-hdd.img').read_bytes()
    if (dist/'CastiOS-x64-preview.iso').is_file():
        assert archive.read('CastiOS/dist/CastiOS-x64-preview.iso')==(dist/'CastiOS-x64-preview.iso').read_bytes()
print('Paquete verificado:',dist)
