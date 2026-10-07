#!/usr/bin/env bash
# Open PrusaSlicer or UVtools in the container's browser desktop (https://localhost:3001).
#
#   docker compose exec -u abc freecad /config/designs/gui.sh prusaslicer [model.stl]
#   docker compose exec -u abc freecad /config/designs/gui.sh uvtools [model.ctb]
#
# --wait runs the app in the foreground (used as the autostart of the dedicated
# prusaslicer/uvtools desktops, whose watchdog relaunches the app when it exits).
#
# Both apps need the Xwayland display :0. The desktop session exports DISPLAY=:1,
# where they fail to open windows, so this script sets the display explicitly.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE="${SCRIPT_DIR}/printers/creality_ld002h.ini"

export DISPLAY=:0
export GDK_BACKEND=x11
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/config/.XDG}"

WAIT=0
if [[ "${1:-}" == "--wait" ]]; then WAIT=1; shift; fi

app="${1:-}"
[[ $# -gt 0 ]] && shift

case "$app" in
  prusaslicer) cmd=(prusa-slicer --load "$PROFILE" "$@") ;;
  uvtools)     cmd=(uvtools "$@") ;;
  *)           echo "Usage: $(basename "$0") [--wait] prusaslicer|uvtools [file]" >&2; exit 1 ;;
esac

if [[ $WAIT -eq 1 ]]; then
  exec "${cmd[@]}"
fi

# Detach so the app keeps running after `docker compose exec` returns
setsid nohup "${cmd[@]}" >"/tmp/gui-${app}.log" 2>&1 &
echo "Started ${app}; open https://localhost:3001 (log: /tmp/gui-${app}.log)"
