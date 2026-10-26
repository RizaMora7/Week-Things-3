#!/bin/zsh
# Captura la ventana principal de Semana con screencapture -R (System Events no expone
# el id de la ventana en esta app). $1 = archivo de salida.
HERE="$(cd "$(dirname "$0")/.." && pwd)"     # raíz del proyecto (esto está en Tools/)
out="$1"
[ -z "$out" ] && { echo "falta archivo de salida"; exit 2; }
case "$out" in /*) ;; *) out="$HERE/$out" ;; esac
geom=$(osascript -e 'tell application "System Events" to tell process "Semana" to get {(position of window 1), (size of window 1)}' 2>/dev/null)
geom=${geom//, / }
set -- ${(z)geom}
if [ "$#" -lt 4 ]; then echo "sin ventana ($geom)"; exit 1; fi
screencapture -o -x -R"$1,$2,$3,$4" "$out" && echo "ok $out ($3x$4)"
