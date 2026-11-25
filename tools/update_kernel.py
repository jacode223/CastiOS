"""Build a new bootable disk from edited kernel sources; VM must be powered off."""
import argparse
import subprocess
from pathlib import Path
ROOT = Path(__file__).resolve().parent.parent
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('old_disk', type=Path)
p.add_argument('new_disk', type=Path)
a = p.parse_args()
if not a.old_disk.is_file() or a.new_disk.exists() or a.new_disk.is_symlink():
    p.error('Origen inexistente o destino ya existente')
subprocess.run(['bash', str(ROOT/'build.sh')], cwd=ROOT, check=True)
boot = (ROOT/'build/installer.iso').read_bytes()
old = a.old_disk.read_bytes()
if len(boot) >= 16*1024*1024 or len(old) < 32*1024*1024:
    p.error('Imagen incompatible o kernel demasiado grande')
with a.new_disk.open('xb') as out:
    out.write(boot)
    out.write(bytes(16*1024*1024-len(boot)))
    out.write(old[16*1024*1024:])
print('Kernel compilado. Apaga la VM, conecta', a.new_disk, 'y reinicia para aplicar los cambios.')
