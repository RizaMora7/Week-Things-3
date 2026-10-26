#!/bin/zsh
# demo.sh — construye las bases inventadas y abre la app apuntando a ellas.
#
#   zsh Tools/demo.sh              # tablero semanal de ejemplo
#   zsh Tools/demo.sh --day        # vista del día
#
# No toca tus datos: la app recibe las rutas por variable de entorno
# (SEMANA_THINGS_DB / SEMANA_CALENDAR_DB) y lee solo build/demo/.
set -e
HERE="$(cd "$(dirname "$0")/.." && pwd)"
bash "$HERE/Tools/makedemo.sh"

export SEMANA_THINGS_DB="$HERE/build/demo/things.sqlite"
export SEMANA_CALENDAR_DB="$HERE/build/demo/calendar.sqlite"

BIN="$HERE/build/Semana.app/Contents/MacOS/Semana"
[ -x "$BIN" ] || { echo "primero compila: ./build.sh"; exit 1; }
echo "→ demo: $SEMANA_THINGS_DB"
"$BIN" "$@"
