#!/bin/zsh
# mkiconset.sh — convierte un maestro cuadrado PNG en AppIcon.icns.
#
#   zsh Tools/mkiconset.sh build/master-light.png Resources/AppIcon
#
# Escribe Resources/AppIcon.iconset/ (las diez medidas que pide iconutil) y
# Resources/AppIcon.icns. El maestro de esta app sale de Tools/iconpack.swift,
# que recorta la lámina de referencia y le da esquinas con transparencia real.
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

# Ojo con dos cosas: el prefijo es literalmente `icon_` (no el nombre de la app) y
# solo existen las medidas 16, 32, 128, 256 y 512 con su @2x. Con cualquier otro
# nombre iconutil falla y solo dice "Failed to generate ICNS".
for s in 16 32 128 256 512; do
  sips -z $s $s "$MASTER" --out "$ICONSET/icon_${s}x${s}.png"     >/dev/null
  d=$((s * 2))
  sips -z $d $d "$MASTER" --out "$ICONSET/icon_${s}x${s}@2x.png"  >/dev/null
done
# 1024 solo existe como @2x del de 512; iconutil lo pide con ese nombre.
iconutil -c icns "$ICONSET" -o "$DIR/$BASE.icns"
echo "→ $DIR/$BASE.icns  ($(du -h "$DIR/$BASE.icns" | cut -f1), 10 medidas)"
