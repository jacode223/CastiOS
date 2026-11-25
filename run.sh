#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")"
[[ -f build/CastiOS.iso && -f build/asfs4.img ]] || bash build.sh
exec qemu-system-i386 -m 256 -boot d -cdrom build/CastiOS.iso -drive file=build/asfs4.img,format=raw,if=ide,index=0 "$@"
