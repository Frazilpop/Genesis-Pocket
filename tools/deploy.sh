#!/bin/bash
# Genesis for Analogue Pocket: put the core on the card.
#
#   tools/deploy.sh [/Volumes/NAME]   copy the core onto the Pocket's card
#   tools/deploy.sh --status          is the current build on the card?
#
# Copies dist/Cores/frazilpop.Genesis (the bitstream tools/build.sh made and
# the core's JSONs) onto the card, replacing the folder whole, and checks the
# bitstream byte for byte. The card is the volume with Analogue_Pocket.json at
# its root, in the Mac's reader or the Pocket's own over USB.
#
# The games are the card's own: every Genesis core reads Assets/genesis/common,
# so nothing is copied there. The platform (Platforms/genesis.json and its
# image) is shared with the other Genesis cores. The JSON is copied only when
# the card has none, so the card's own name stays. The image is this repo's
# (dyreschlock's Sega Genesis banner) and is put there whenever the card's
# differs, so those cores show it too.
#
# One copy to the card at a time, under /tmp/pocket-card.lock (shared with
# other cores' deploy scripts). Nothing ejects the card.
# Each verified copy is recorded in build/deployed.txt.

set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
CORE="frazilpop.Genesis"
DIST="$REPO/dist"
BIN="$DIST/Cores/$CORE/bitstream.rbf_r"
RECORD="$REPO/build/deployed.txt"
[ -f "$BIN" ] || { echo "no $BIN - run tools/build.sh first"; exit 1; }

VOL="" STATUS=0
for a in "$@"; do
	case "$a" in --status) STATUS=1 ;; *) VOL="$a" ;; esac
done

built() { stat -f '%Sm' -t '%Y-%m-%d %H:%M' "$BIN"; }
sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
find_card() {
	local v
	for v in /Volumes/*; do
		[ -f "$v/Analogue_Pocket.json" ] && { VOL="$v"; return 0; }
	done
	return 1
}

if [ $STATUS = 1 ]; then
	s=$(sha "$BIN")
	echo "Build:   $(built), SHA-256 ${s:0:12}"
	last=$(sed -n 's/^sha256 //p' "$RECORD" 2>/dev/null || true)
	if [ -z "$last" ]; then
		echo "Card:    no deploy recorded"
	else
		echo "Card:    got the build of $(sed -n 's/^built //p' "$RECORD") at $(sed -n 's/^deployed //p' "$RECORD"), SHA-256 ${last:0:12}"
	fi
	if [ -n "$VOL" ] || find_card; then
		f="$VOL/Cores/$CORE/bitstream.rbf_r"
		[ -f "$f" ] && last=$(sha "$f") || last=none
		echo "         (checked on the mounted card, $VOL: ${last:0:12})"
	fi
	if [ "$last" = "$s" ]; then echo "UP TO DATE - the card has the current build"
	else echo "NOT ON THE CARD - the current build has not been deployed: tools/deploy.sh"; exit 1; fi
	exit 0
fi

[ -n "$VOL" ] || find_card || { echo "No Analogue Pocket SD card found (no volume with Analogue_Pocket.json)"; exit 1; }
[ -f "$VOL/Analogue_Pocket.json" ] || { echo "$VOL is not the Pocket's card"; exit 1; }

LOCK=/tmp/pocket-card.lock
release() {
	[ "$(cat "$LOCK/pid" 2>/dev/null)" = "$$" ] && rm -rf "$LOCK"
	return 0
}
trap release EXIT
until mkdir "$LOCK" 2>/dev/null; do
	holder=$(cat "$LOCK/pid" 2>/dev/null || true)
	if [ -n "$holder" ] && ! kill -0 "$holder" 2>/dev/null; then rm -rf "$LOCK"; continue; fi
	[ -n "${told:-}" ] || { echo "Waiting for another deploy to the card (pid ${holder:-?})..."; told=1; }
	sleep 1
done
echo $$ >"$LOCK/pid"

# the core: its folder replaced whole
rm -rf "$VOL/Cores/$CORE"
mkdir -p "$VOL/Cores"
cp -R "$DIST/Cores/$CORE" "$VOL/Cores/"
cmp -s "$BIN" "$VOL/Cores/$CORE/bitstream.rbf_r" || { echo "the bitstream on the card differs from the build"; exit 1; }
echo "Copied the core ($CORE) to $VOL"

# the platform's name, only when the card has none; its image, when it differs
mkdir -p "$VOL/Platforms/_images"
if [ ! -f "$VOL/Platforms/genesis.json" ]; then
	cp "$DIST/Platforms/genesis.json" "$VOL/Platforms/"
	echo "Copied the Genesis platform (the card had none)"
fi
if ! cmp -s "$DIST/Platforms/_images/genesis.bin" "$VOL/Platforms/_images/genesis.bin"; then
	cp "$DIST/Platforms/_images/genesis.bin" "$VOL/Platforms/_images/"
	echo "Copied the Genesis banner (the card's differed; every Genesis core shows it)"
fi
mkdir -p "$VOL/Assets/genesis/common"

mkdir -p "$(dirname "$RECORD")"
{
	echo "sha256 $(sha "$BIN")"
	echo "built $(built)"
	echo "commit $(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo '?')"
	echo "deployed $(date '+%Y-%m-%d %H:%M')"
	echo "card $VOL"
} >"$RECORD"
echo "Done - the card is left mounted; eject it before taking it out."
