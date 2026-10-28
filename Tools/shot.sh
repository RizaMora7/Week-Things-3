#!/bin/zsh
# Captures Semana's main window with screencapture -R (System Events doesn't expose
# the window id for this app). $1 = output file.
HERE="$(cd "$(dirname "$0")/.." && pwd)"     # project root (this lives in Tools/)
out="$1"
[ -z "$out" ] && { echo "missing output file"; exit 2; }
case "$out" in /*) ;; *) out="$HERE/$out" ;; esac
geom=$(osascript -e 'tell application "System Events" to tell process "Semana" to get {(position of window 1), (size of window 1)}' 2>/dev/null)
geom=${geom//, / }
set -- ${(z)geom}
if [ "$#" -lt 4 ]; then echo "no window ($geom)"; exit 1; fi
screencapture -o -x -R"$1,$2,$3,$4" "$out" && echo "ok $out ($3x$4)"
