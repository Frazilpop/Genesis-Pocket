#!/bin/bash
# The reference for the core's timing: BlastEm (cycle-exact, where MAME's Genesis
# is not) on the same ROM, every frame's CRC in a frames.txt beside tools/sim.sh's,
# for sim/genesis/lag.py and, for the frames kept, sim/genesis/compare.py.
#   bash tools/blastem-frames.sh rom frames [--out DIR] [--keep F,F|all] [--no-refresh] [--vram F] [--region J|U|E]
# Out in build/blastem_genesis unless --out. Its frame N is numbered N + 1, as MAME's
# are, so the names pair up with the sim's. --no-refresh leaves out the 68000's
# refresh wait (2 of its clocks in every 128), for how far it moves a game.
# BlastEm has no frame dump of its own, so this fetches its source, pinned by its
# checksum, puts sim/genesis/blastem-dump.patch on it and builds it, the first time:
# build/tools/blastem, with Homebrew's glew, sdl2-compat and pkgconf to build against.
# --vram F writes VRAM, the registers and the sprite cache of frame F.
set -euo pipefail
cd "$(dirname "$0")/.."
[ $# -ge 2 ] || { echo "usage: bash tools/blastem-frames.sh rom frames [--out DIR] [--keep F,F|all] [--no-refresh] [--vram F] [--region J|U|E]"; exit 2; }
ROM=$(cd "$(dirname "$1")" && pwd)/$(basename "$1"); N=$2; shift 2
OUT=build/blastem_genesis; KEEP=; REFRESH=2; VRAM=; REGION=()
while [ $# -gt 0 ]; do case "$1" in
  --out) OUT=$2; shift 2;;
  --keep) KEEP=$2; shift 2;;
  --no-refresh) REFRESH=0; shift;;
  --vram) VRAM=$2; shift 2;;
  --region) REGION=(-r "$2"); shift 2;;
  *) echo "what's $1?"; exit 2;;
esac; done

B=$PWD/build/tools/blastem
URL=https://www.retrodev.com/repos/blastem/archive/v1.0.0.tar.gz
# (of the tar inside: the server gzips it afresh, so the .gz's own checksum is not fixed. Mercurial's node 2b2a182f45226)
SUM=8588218072c829163cd71bd92500699821cb4034296e998f7dee4f6e1fcfcdc5
# (it links against the first two, so each run wants them there)
for f in glew sdl2-compat pkgconf; do
  [ -d "$(brew --prefix)/opt/$f" ] || { echo "brew install $f"; brew install "$f"; }
done
KEY=$(cat sim/genesis/blastem-dump.patch tools/blastem-frames.sh | shasum | cut -c1-16)
if [ "$(cat "$B/key" 2>/dev/null)" != "$KEY" ] || [ ! -x "$B/src/blastem" ]; then
  echo "Building BlastEm with its frame dump, the first time (about 3 minutes)"
  mkdir -p "$B"
  if [ "$(gunzip -c "$B/blastem-v1.0.0.tar.gz" 2>/dev/null | shasum -a 256 | cut -d' ' -f1)" != "$SUM" ]; then
    echo "Fetching BlastEm 1.0.0's source"
    curl -fsSL -o "$B/blastem-v1.0.0.tar.gz" "$URL"
    [ "$(gunzip -c "$B/blastem-v1.0.0.tar.gz" | shasum -a 256 | cut -d' ' -f1)" = "$SUM" ] || { echo "BlastEm's source is not the one this was checked on"; exit 1; }
  fi
  rm -rf "$B/src"; mkdir -p "$B/src"
  tar xzf "$B/blastem-v1.0.0.tar.gz" --strip-components=1 -C "$B/src"
  patch -s -p1 -d "$B/src" < sim/genesis/blastem-dump.patch
  PATH=$(brew --prefix)/bin:$PATH make -C "$B/src" -j"$(sysctl -n hw.ncpu)" blastem HOST_ZLIB=1 OPT=-O2 > "$B/make.log" 2>&1 \
    || { tail -20 "$B/make.log"; exit 1; }
  echo "$KEY" > "$B/key"
fi

# (no save left from the last run: a game finding one boots otherwise, and the sim starts with none)
rm -rf "$B/home/.local/share/blastem"
mkdir -p "$OUT" "$B/home"
OUT_ABS=$(cd "$OUT" && pwd)
rm -f "$OUT_ABS"/f_*.png "$OUT_ABS"/frames.txt
# (HOME its own, for its config and saves; it reads default.cfg from beside itself;
# -b is headless, and its count, which runs double there, is only ever a backstop)
( cd "$B/src" && HOME="$B/home" BLASTEM_DUMP="$OUT_ABS" BLASTEM_FRAMES="$N" BLASTEM_KEEP="$KEEP" BLASTEM_REFRESH="$REFRESH" \
  BLASTEM_VRAM="$VRAM" ./blastem -b 100000000 -g ${REGION[@]+"${REGION[@]}"} "$ROM" > "$OUT_ABS/blastem.log" 2>&1 ) || true
L=$(wc -l < "$OUT_ABS/frames.txt" | tr -d ' ')
[ "$L" -ge "$((N - 1))" ] || { tail -5 "$OUT_ABS/blastem.log"; echo "BlastEm stopped at $L frames of $N"; exit 1; }
echo "$L frames from BlastEm in $OUT (refresh wait $REFRESH)"
