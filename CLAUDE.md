# CLAUDE.md

FreeCAD-in-Docker workspace for parametric CAD designs, resin-printed on a **Creality LD-002H** (MSLA, 1620×2560 px, 82.62×130.56 mm, 160 mm Z, reads Chitubox `.ctb`).

## Setup / repair
Use the project skill `setting-up-cad-print-env`, which runs `bash .claude/skills/setting-up-cad-print-env/setup.sh`. It covers fresh machines, rebuilds and troubleshooting.

## Pipeline
FreeCAD script (`designs/*.py`) → `.FCStd` + `.stl` → `designs/slice_ld002h.sh` → PrusaSlicer `--export-sla` (`.sl1`) → `UVtoolsCmd convert … ChituboxFile -v 3` → `.ctb` → USB stick.

PrusaSlicer can't write `.ctb`, and UVtools can't slice an STL. Both steps are needed.

## Commands (run from repo root, on the host)
```bash
docker compose exec -u abc freecad /opt/freecad/usr/bin/freecadcmd /config/designs/<design>.py   # generate model
docker compose exec -u abc freecad /config/designs/slice_ld002h.sh /config/designs/<model>.stl   # slice (--help for options)
docker compose exec -u abc freecad UVtoolsCmd --no-progress print-properties /config/designs/<model>.ctb   # inspect
docker compose build && docker compose up -d   # rebuild slicer layer / apply compose changes
```
- Always pass `-u abc`. Without it, files in `designs/` end up owned by root.
- `/config/designs` in the containers is `./designs` on the host.
- GUIs: FreeCAD https://localhost:3001, PrusaSlicer :3002, UVtools :3003.

## Layout
| Path | Role |
|------|------|
| `Dockerfile` | `freecad:1.1.3`, the linuxserver FreeCAD base. Build once; it pulls ~6 GB. |
| `Dockerfile.slicer` | `freecad-slicer:1.1.3`: adds PrusaSlicer (Debian) + UVtools (`.deb`, pinned version) and a `DESKTOP_APP` autostart dispatcher |
| `docker-compose.yml` | Services `freecad`, `prusaslicer`, `uvtools`, all on the same image, each with its own `config*/` (gitignored) |
| `designs/printers/creality_ld002h.ini` | PrusaSlicer SLA profile. The printer section comes from UVtools' bundled `Creality LD-002H.ini`. The material defaults (2.5 s / 30 s, 6 bottom layers) are for generic standard resin. |
| `designs/slice_ld002h.sh` | STL → `.ctb`. CLI flags override the `.ini`. |
| `designs/gui.sh` | Launches PrusaSlicer/UVtools on Xwayland `DISPLAY=:0`. `--wait` runs it in the foreground for autostart. |

## Design script conventions (see `designs/bcc_beam_lattice.py`)
- Put parameters as UPPER_CASE constants at the top, in mm.
- Build the geometry with `Part`, fuse it into one solid, then `removeSplitter()`.
- Write `<name>.FCStd` and `<name>.stl` next to the script. Mesh with `MeshPart.meshFromShape`, `LinearDeflection=0.1`.
- Call `main()` at module level. `freecadcmd` executes the file and has no `__main__` guard.
- Keep outputs (`*.FCStd`, `*.stl`, `*.sl1`, `*.ctb`) out of git. Regenerate them instead.

## Gotchas
- **Desktop terminal launch:** PrusaSlicer and UVtools crash if started with the desktop's `DISPLAY=:1`. Go through `gui.sh`.
- **Pad without supports:** this needs `pad_around_object_everywhere = 1`. Otherwise PrusaSlicer emits no pad, and only the beam tips touch the plate.
- **PrusaSlicer boolean CLI overrides:** use `--flag` / `--no-flag`, not `--flag 0`.
- **UVtools global options:** `--no-progress` and `-q` go before the subcommand. `convert … auto` ignores the output filename, so use the explicit `ChituboxFile -v 3`.
- **Proxy networks:** compose passes `http(s)_proxy` from the shell into builds and containers. Without them, PrusaSlicer shows "Archive Database Manifest … Error 28".
- **FreeCAD desktop menu:** the container restores `config/.config/labwc/menu.xml` from `menu.xml.bak` on every start, so edit the `.bak`.
- **Recreating containers:** `docker compose up -d` recreates any container whose config changed. Unsaved GUI work in it is lost, so check with the user first.
- **Mirroring / orientation:** these come from the UVtools profile and haven't been validated by a real print. Use an asymmetric test print before trusting them.
