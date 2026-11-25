#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")"
[[ -f build/CastiOS.iso ]] || bash build.sh
python3 -c 'from pathlib import Path; p=Path("build/install-target-grub.img"); p.exists() or p.open("xb").truncate(32*1024*1024)'
exec qemu-system-i386 -m 256 -boot d -cdrom build/CastiOS.iso -drive file=build/install-target-grub.img,format=raw,if=ide,index=0 "$@"
