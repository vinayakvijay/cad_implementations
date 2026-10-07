#!/usr/bin/env bash
# Set up the FreeCAD + PrusaSlicer + UVtools (Creality LD-002H) Docker environment
# from a fresh clone of this repo. Safe to re-run: finished steps are skipped.
#
#   bash .claude/skills/setting-up-cad-print-env/setup.sh [--check] [--no-start] [--rebuild-base]
#
#   --check         preflight only, change nothing
#   --no-start      build images but do not start containers
#   --rebuild-base  rebuild freecad:1.1.3 even if it exists (pulls ~6 GB)
set -euo pipefail

CHECK_ONLY=0; NO_START=0; REBUILD_BASE=0
for arg in "$@"; do
  case "$arg" in
    --check)        CHECK_ONLY=1 ;;
    --no-start)     NO_START=1 ;;
    --rebuild-base) REBUILD_BASE=1 ;;
    -h|--help)      sed -n 2,10p "$0"; exit 0 ;;
    *)              echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
cd "$ROOT"

BASE_IMAGE=freecad:1.1.3
SERVICES=(freecad prusaslicer uvtools)

step() { printf '\n==> %s\n' "$*"; }
ok()   { printf '    ok: %s\n' "$*"; }
warn() { printf '    WARN: %s\n' "$*"; }
die()  { printf '    ERROR: %s\n' "$*" >&2; exit 1; }

# Ownership of files written into ./designs and ./config-* follows the host user.
export PUID="${PUID:-$(id -u)}" PGID="${PGID:-$(id -g)}"

# ---------------------------------------------------------------- preflight
step "Preflight"
[[ -f docker-compose.yml && -f Dockerfile.slicer ]] || die "run from a clone of the cad_implementations repo ($ROOT)"
command -v docker >/dev/null || die "docker not installed (https://docs.docker.com/engine/install/)"
docker info >/dev/null 2>&1 || die "docker daemon not reachable (is it running? is $USER in the docker group?)"
docker compose version >/dev/null 2>&1 || die "docker compose v2 plugin missing"
ok "docker $(docker version --format '{{.Server.Version}}'), $(docker compose version --short)"

arch="$(uname -m)"
[[ "$arch" == "x86_64" ]] && ok "arch $arch" \
  || warn "arch $arch: images are x86_64 (UVtools .deb is linux-x64); expect emulation or failure"

free_gb="$(df -Pk /var/lib/docker 2>/dev/null | awk 'NR==2{print int($4/1048576)}' || true)"
if [[ -n "$free_gb" && "$free_gb" -lt 15 ]]; then warn "only ${free_gb} GB free for docker; ~8 GB needed"; fi

if [[ -n "${https_proxy:-${HTTPS_PROXY:-}}" ]]; then
  ok "proxy ${https_proxy:-$HTTPS_PROXY} (passed to builds and containers)"
  docker info 2>/dev/null | grep -qi 'https proxy' \
    || warn "docker daemon has no proxy configured; base image pull may fail (see SKILL.md)"
fi

if [[ -z "$(docker compose ps -q 2>/dev/null)" ]]; then
  for p in $(docker compose config 2>/dev/null | sed -n 's/.*published: "\([0-9]*\)".*/\1/p'); do
    if (exec 3<>"/dev/tcp/127.0.0.1/$p") 2>/dev/null; then
      die "port $p already in use by something else"
    fi
  done
  ok "ports free"
fi

docker image inspect "$BASE_IMAGE" >/dev/null 2>&1 \
  && ok "base image $BASE_IMAGE present" || ok "base image $BASE_IMAGE missing (will build, ~6 GB pull)"

if [[ $CHECK_ONLY -eq 1 ]]; then echo; echo "Preflight passed (--check: nothing changed)."; exit 0; fi

# ------------------------------------------------------------------ folders
step "App data folders"
# Create as the host user; if docker creates them they end up root-owned.
mkdir -p config config-prusaslicer config-uvtools
ok "config/ config-prusaslicer/ config-uvtools/"

# ------------------------------------------------------------------- images
PROXY_ARGS=()
for v in http_proxy https_proxy HTTP_PROXY HTTPS_PROXY; do
  if [[ -n "${!v:-}" ]]; then PROXY_ARGS+=(--build-arg "$v=${!v}"); fi
done

step "Base image $BASE_IMAGE"
if [[ $REBUILD_BASE -eq 1 ]] || ! docker image inspect "$BASE_IMAGE" >/dev/null 2>&1; then
  docker build ${PROXY_ARGS[@]+"${PROXY_ARGS[@]}"} -t "$BASE_IMAGE" .
fi
ok "$BASE_IMAGE"

step "Slicer image (PrusaSlicer + UVtools)"
docker compose build
ok "freecad-slicer:1.1.3"

if [[ $NO_START -eq 1 ]]; then echo; echo "Images built (--no-start)."; exit 0; fi

# ------------------------------------------------------------------- start
step "Start containers"
docker compose up -d
ok "${SERVICES[*]}"

# --------------------------------------------------------- desktop menu
step "FreeCAD desktop menu entries (PrusaSlicer / UVtools)"
# The container restores menu.xml from menu.xml.bak on every start, so edit both.
menu_bak=config/.config/labwc/menu.xml.bak
for _ in $(seq 60); do [[ -f "$menu_bak" ]] && break; sleep 2; done
if [[ ! -f "$menu_bak" ]]; then
  warn "$menu_bak not created yet; re-run this script later to add the entries"
elif grep -q 'gui.sh prusaslicer' "$menu_bak"; then
  ok "already present"
else
  # insert before the first </menu> (awk, so it also works with BSD tools)
  awk '!done && /<\/menu>/ {
         print "<item label=\"PrusaSlicer\"><action name=\"Execute\"><command>/config/designs/gui.sh prusaslicer</command></action></item>"
         print "<item label=\"UVtools\"><action name=\"Execute\"><command>/config/designs/gui.sh uvtools</command></action></item>"
         done=1 }
       { print }' "$menu_bak" > "$menu_bak.tmp" && mv "$menu_bak.tmp" "$menu_bak"
  cp "$menu_bak" config/.config/labwc/menu.xml
  ok "added (visible after the next container restart)"
fi

# ------------------------------------------------------------------- verify
step "Verify"
ex() { docker compose exec -T -u abc freecad "$@"; }
for _ in $(seq 30); do ex true >/dev/null 2>&1 && break; sleep 2; done
ok "$(ex prusa-slicer --help | head -1 | cut -d' ' -f1)"
ok "UVtoolsCmd $(ex UVtoolsCmd --version)"

if [[ ! -f designs/bcc_beam_lattice.stl ]]; then
  ex /opt/freecad/usr/bin/freecadcmd /config/designs/bcc_beam_lattice.py >/dev/null
fi
[[ -f designs/bcc_beam_lattice.stl ]] && ok "FreeCAD STL generation" || die "bcc_beam_lattice.stl was not generated"

summary="$(ex /config/designs/slice_ld002h.sh /config/designs/bcc_beam_lattice.stl -o /tmp/setup-check.ctb 2>&1)" \
  || { echo "$summary"; die "slicing failed"; }
for want in 'Version: 3' 'ResolutionX: 1620' 'ResolutionY: 2560'; do
  grep -q "^$want$" <<<"$summary" || { echo "$summary"; die "slice summary missing '$want'"; }
done
ok "slice -> .ctb v3, 1620x2560 ($(grep -m1 '^LayerCount' <<<"$summary"))"

echo
echo "Desktops (HTTPS, accept the self-signed certificate):"
for s in "${SERVICES[@]}"; do
  hostport="$(docker compose port "$s" 3001 | sed 's/^0\.0\.0\.0/localhost/; s/^\[::\]/localhost/')"
  code=000
  for _ in $(seq 30); do
    code="$(curl -sk --noproxy '*' -o /dev/null -w '%{http_code}' "https://$hostport" || true)"
    [[ "$code" == 200 ]] && break; sleep 2
  done
  printf '    %-12s https://%s  (HTTP %s)\n' "$s" "$hostport" "$code"
done
echo
echo "Setup complete."
