#!/bin/bash
# Genesis Plus GX, the libretro core RetroArch runs, without a window (tools/gpgx-save.c): a game,
# a save loaded and written as RetroArch does it, buttons from a script, frames as pictures.
#   bash tools/gpgx-save.sh ROM OUTDIR FRAMES [--srm IN] [--input SCRIPT] [--dump F,F,...]
# The save it leaves is OUTDIR/game.srm. Built the first time into build/tools/gpgx, at a fixed
# commit (its licence is non-commercial: fetched to build, never kept in the repo).
set -euo pipefail
cd "$(dirname "$0")/.."
G=build/tools/gpgx
REV=b9c2316441978d4015ba30e9a95d9b0e6f8ee981
SRC=$G/Genesis-Plus-GX-$REV
if [ ! -f "$SRC/genesis_plus_gx_libretro.dylib" ]; then
  mkdir -p "$G"
  curl -sfL "https://github.com/libretro/Genesis-Plus-GX/archive/$REV.tar.gz" -o "$G/gpgx-$REV.tar.gz"
  tar xzf "$G/gpgx-$REV.tar.gz" -C "$G"
  make -C "$SRC" -f Makefile.libretro -j8 > "$G/make.log" 2>&1 || { tail -20 "$G/make.log"; exit 1; }
fi
if [ ! -x "$G/gpgx-save" ] || [ tools/gpgx-save.c -nt "$G/gpgx-save" ]; then
  cc -O2 -I"$SRC/libretro/libretro-common/include" -o "$G/gpgx-save" tools/gpgx-save.c
fi
[ $# -ge 3 ] || { echo "gpgx-save.sh ROM OUTDIR FRAMES [--srm IN] [--input SCRIPT] [--dump F,F,...]" >&2; exit 2; }
rom=$1 out=$2; shift 2
mkdir -p "$out"
"$G/gpgx-save" "$PWD/$SRC/genesis_plus_gx_libretro.dylib" "$rom" "$out" "$@"
