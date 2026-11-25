#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")"
[[ -f build/CastiOS-hdd.img ]] || python3 tools/install_disk.py build/CastiOS-hdd.img
exec qemu-system-i386 -m 256 -boot c -drive file=build/CastiOS-hdd.img,format=raw,if=ide,index=0 "$@"
