#!/bin/bash
# Fabrique icon/icon.icns (et docs/icon.png) à partir de icon/make_icon.swift.
# Usage : scripts/make_icns.sh
set -euo pipefail
cd "$(dirname "$0")/.."

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

swiftc -O icon/make_icon.swift -o "$WORK/make_icon"
"$WORK/make_icon" "$WORK/icon_1024.png"

SET="$WORK/icon.iconset"
mkdir -p "$SET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$WORK/icon_1024.png" --out "$SET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z $d $d "$WORK/icon_1024.png" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o icon/icon.icns
mkdir -p docs
cp "$WORK/icon_1024.png" docs/icon.png
echo "OK : icon/icon.icns et docs/icon.png"
