#!/bin/bash
# GHDL, which translates the VDP, the Z80 (T80) and the SVP from VHDL to
# Verilog for the simulation (tools/sim.sh), into build/tools/ghdl. Homebrew's
# cask for it is disabled (it fails Gatekeeper's check), so this takes the
# release from GHDL's GitHub, pinned by its checksum. curl sets no
# quarantine, so it runs as it is. About 40 MB down, 120 MB unpacked.
#   bash tools/get-ghdl.sh          (nothing to do when it is there)
set -euo pipefail
cd "$(dirname "$0")/.."
VER=6.0.0
NAME=ghdl-llvm-$VER-macos15-aarch64
SHA=69beb5913a490b5971980bd045af6a63b6f52e861b444fa990bffac436587478
DIR=build/tools/ghdl
if [ -x "$DIR/bin/ghdl" ] && [ "$(cat "$DIR/VERSION" 2>/dev/null)" = "$VER" ]; then exit 0; fi
[ "$(uname -m)" = arm64 ] || { echo "GHDL's macOS release is for Apple silicon only; this Mac is $(uname -m)"; exit 1; }
echo "Fetching GHDL $VER (about 40 MB)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
curl -fsSL -o "$TMP/ghdl.tgz" "https://github.com/ghdl/ghdl/releases/download/v$VER/$NAME.tar.gz"
echo "$SHA  $TMP/ghdl.tgz" | shasum -a 256 -c - >/dev/null || { echo "GHDL's download does not match its checksum"; exit 1; }
tar xzf "$TMP/ghdl.tgz" -C "$TMP"
rm -rf "$DIR"; mkdir -p "$(dirname "$DIR")"
mv "$TMP/$NAME" "$DIR"
echo "$VER" > "$DIR/VERSION"
"$DIR/bin/ghdl" --version | head -1
