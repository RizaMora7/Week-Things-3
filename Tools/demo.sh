#!/bin/zsh
# demo.sh — builds the made-up databases and opens the app pointed at them.
#
#   zsh Tools/demo.sh              # sample weekly board
#   zsh Tools/demo.sh --day        # day view
#
# Doesn't touch your data: the app receives the paths via environment variables
# (SEMANA_THINGS_DB / SEMANA_CALENDAR_DB) and only reads build/demo/.
set -e
HERE="$(cd "$(dirname "$0")/.." && pwd)"
bash "$HERE/Tools/makedemo.sh"

export SEMANA_THINGS_DB="$HERE/build/demo/things.sqlite"
export SEMANA_CALENDAR_DB="$HERE/build/demo/calendar.sqlite"

BIN="$HERE/build/Semana.app/Contents/MacOS/Semana"
[ -x "$BIN" ] || { echo "build first: ./build.sh"; exit 1; }
echo "→ demo: $SEMANA_THINGS_DB"
"$BIN" "$@"
