#!/usr/bin/env bash
# Rebuild the supplied NASM as static i386; the OS supplies its required ABI.
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
mkdir -p build/nasm-source
python3 - <<'PY'
from pathlib import Path
import zipfile
with zipfile.ZipFile('vendor/NASM-3.02-source.zip') as z:
    root=Path('build/nasm-source').resolve()
    for name in z.namelist():
        if not (root/name).resolve().is_relative_to(root):raise SystemExit('Ruta ZIP invalida')
    z.extractall(root)
PY
cd build/nasm-source/netwide-assembler-nasm-8f1fb54
bash autogen.sh
CC='gcc -m32' CFLAGS='-O2' LDFLAGS='-static' bash configure --host=i686-linux-gnu --without-zlib
make -j"${JOBS:-2}" nasm
strip -o ../../nasm32 nasm
printf 'NASM i386 listo. Ejecuta bash build.sh y make test.\n'
