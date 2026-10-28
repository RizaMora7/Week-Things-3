#!/bin/zsh
# mkiconset.sh — turns a square PNG master into AppIcon.icns.
#
#   zsh Tools/mkiconset.sh build/master-light.png Resources/AppIcon
#
# Writes Resources/AppIcon.iconset/ (the ten sizes iconutil wants) and
# Resources/AppIcon.icns. This app's master comes from Tools/iconpack.swift,
# which crops the reference sheet and gives it corners with real transparency.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
MASTER="${1:?falta el PNG maestro}"
OUT="${2:?falta la ruta base de salida (sin extensión)}"

BASE="$(basename "$OUT")"
DIR="$(dirname "$OUT")"
ICONSET="$DIR/$BASE.iconset"
mkdir -p "$DIR"
[ -d "$ICONSET" ] && mv "$ICONSET" "$DIR/.scratch-$BASE.iconset" 2>/dev/null || true
mkdir -p "$ICONSET"

# Watch out for two things: the prefix is literally `icon_` (not the app's name) and
# only sizes 16, 32, 128, 256 and 512 exist, each with its @2x. With any other
# name iconutil fails and only says "Failed to generate ICNS".
for s in 16 32 128 256 512; do
  sips -z $s $s "$MASTER" --out "$ICONSET/icon_${s}x${s}.png"     >/dev/null
  d=$((s * 2))
  sips -z $d $d "$MASTER" --out "$ICONSET/icon_${s}x${s}@2x.png"  >/dev/null
done
# 1024 only exists as the @2x of 512; iconutil wants it under that name.
iconutil -c icns "$ICONSET" -o "$DIR/$BASE.icns"
echo "→ $DIR/$BASE.icns  ($(du -h "$DIR/$BASE.icns" | cut -f1), 10 sizes)"
