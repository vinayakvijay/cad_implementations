#!/usr/bin/env bash
# Slice an STL for the Creality LD-002H: STL -> PrusaSlicer (.sl1) -> UVtools (.ctb v3).
#
# Run inside the container:
#   docker compose exec -u abc freecad /config/designs/slice_ld002h.sh /config/designs/bcc_beam_lattice.stl
#
# Defaults come from printers/creality_ld002h.ini (0.05 mm, 2.5 s / 30 s, 6 bottom layers,
# zero-elevation pad, no supports). Output: <model>.ctb next to the STL.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE="${SCRIPT_DIR}/printers/creality_ld002h.ini"
UVTOOLS="${UVTOOLS:-UVtoolsCmd}"
BED_CENTER="41.31,65.28"  # centre of the 82.62 x 130.56 mm build plate

usage() {
  cat <<EOF
Usage: $(basename "$0") <model.stl> [options]

Options:
  -o, --output FILE        Output .ctb path (default: <model>.ctb)
  --layer MM               Layer height (default 0.05)
  --exposure S             Normal layer exposure in seconds (default 2.5)
  --bottom-exposure S      Bottom layer exposure in seconds (default 30)
  --bottom-layers N        Number of bottom layers (default 6)
  --supports               Generate supports (model is elevated on a pad)
  --no-pad                 Do not generate a pad
  --keep-sl1               Keep the intermediate .sl1 file
  -h, --help               Show this help
EOF
}

[[ $# -ge 1 ]] || { usage; exit 1; }

INPUT=""
OUTPUT=""
KEEP_SL1=0
OVERRIDES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--output)       OUTPUT="$2"; shift 2 ;;
    --layer)           OVERRIDES+=(--layer-height "$2" --initial-layer-height "$2"); shift 2 ;;
    --exposure)        OVERRIDES+=(--exposure-time "$2"); shift 2 ;;
    --bottom-exposure) OVERRIDES+=(--initial-exposure-time "$2"); shift 2 ;;
    --bottom-layers)   OVERRIDES+=(--faded-layers "$2"); shift 2 ;;
    --supports)        OVERRIDES+=(--supports-enable --no-pad-around-object --no-pad-around-object-everywhere); shift ;;
    --no-pad)          OVERRIDES+=(--no-pad-enable); shift ;;
    --keep-sl1)        KEEP_SL1=1; shift ;;
    -h|--help)         usage; exit 0 ;;
    -*)                echo "Unknown option: $1" >&2; usage; exit 1 ;;
    *)                 INPUT="$1"; shift ;;
  esac
done

[[ -f "$INPUT" ]] || { echo "STL not found: $INPUT" >&2; exit 1; }
OUTPUT="${OUTPUT:-${INPUT%.*}.ctb}"
SL1="${OUTPUT%.*}.sl1"

echo "==> Slicing $INPUT"
prusa-slicer --export-sla \
  --load "$PROFILE" \
  "${OVERRIDES[@]}" \
  --center "$BED_CENTER" \
  --output "$SL1" \
  "$INPUT"
[[ -f "$SL1" ]] || { echo "PrusaSlicer did not produce $SL1" >&2; exit 1; }

echo "==> Converting to CTB v3: $OUTPUT"
"$UVTOOLS" --no-progress convert "$SL1" ChituboxFile "$OUTPUT" --version 3

[[ $KEEP_SL1 -eq 1 ]] || rm -f "$SL1"

echo "==> Summary"
"$UVTOOLS" --no-progress print-properties "$OUTPUT" \
  | grep -E '^(Version|ResolutionX|ResolutionY|LayerHeight|LayerCount|PrintHeight|BottomLayerCount|BottomExposureTime|ExposureTime|PrintTime|MaterialMilliliters): '
