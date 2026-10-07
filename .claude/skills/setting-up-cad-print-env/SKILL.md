---
name: setting-up-cad-print-env
description: Use when setting up, reinstalling or repairing this repo's FreeCAD + PrusaSlicer + UVtools Docker environment on a computer, including a fresh clone, a new machine, missing images or containers, or a broken slicing pipeline for the Creality LD-002H (.ctb). Also use for desktop errors on ports 3001-3003, such as PrusaSlicer "Failed to download Archive Database Manifest ... Error 28", GUIs that won't open, or root-owned files in designs/.
---

# Setting up the CAD + resin printing environment

## Overview
Three browser desktops from one image, `freecad-slicer:1.1.3`. That image is a thin layer (`Dockerfile.slicer`) on the locally built `freecad:1.1.3` (`Dockerfile`, linuxserver base). All three share `./designs`.

| Service | Link | Starts |
|---------|------|--------|
| freecad | https://localhost:3001 | FreeCAD |
| prusaslicer | https://localhost:3002 | PrusaSlicer (LD-002H profile) |
| uvtools | https://localhost:3003 | UVtools |

## Run the setup script
From the repo root:

```bash
bash .claude/skills/setting-up-cad-print-env/setup.sh --check   # preflight, changes nothing
bash .claude/skills/setting-up-cad-print-env/setup.sh           # full setup + verification
```

You can re-run it safely; finished steps are skipped. It does all of this:
1. Creates the `config*/` folders as the host user.
2. Exports `PUID`/`PGID` from `id`.
3. Builds the base image only if it's missing (`--rebuild-base` forces a rebuild).
4. Runs `docker compose build` and `up -d`.
5. Adds the PrusaSlicer/UVtools menu entries to the FreeCAD desktop.
6. Generates the BCC STL, slices it and checks for a CTB v3 file at 1620x2560.
7. Checks that each link returns HTTP 200.

Report the script's final link table to the user. If a step fails, fix the cause using the table below and re-run. Don't work around the script by hand.

`docker compose up -d` recreates any running container whose config changed. Unsaved GUI work in it is lost, so ask the user before running the script on a machine where the stack is already in use.

## Prerequisites
- Docker Engine plus the compose v2 plugin. The user must be in the `docker` group.
- x86_64, because the UVtools `.deb` is linux-x64. On Apple Silicon or ARM it may run under emulation.
- About 8 GB of disk, and free ports 3000-3003.

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| PrusaSlicer "Failed to download Archive Database Manifest … Error 28" | The container has no proxy on a proxied network | Export `http_proxy`/`https_proxy`/`no_proxy` in the shell, then run `docker compose up -d`. Compose passes them through. |
| The base image pull or `docker build` hangs | The Docker daemon has no proxy | Create a systemd drop-in `/etc/systemd/system/docker.service.d/http-proxy.conf` with `Environment=HTTP_PROXY=… HTTPS_PROXY=… NO_PROXY=localhost,127.0.0.1`, then `systemctl daemon-reload && systemctl restart docker` |
| `prusa-slicer`/`uvtools` typed in a desktop terminal crashes (GtkMessageDialog assert) | The desktop exports `DISPLAY=:1`, but the apps need Xwayland `:0` | Use `/config/designs/gui.sh prusaslicer\|uvtools` |
| Menu entries disappear after a restart | The container restores `menu.xml` from `menu.xml.bak` on every start | Edit `config/.config/labwc/menu.xml.bak` (setup.sh does this) |
| Root-owned files in `designs/` or `config*/` | `docker compose exec` ran without `-u abc`, or Docker created the folders | Use `docker compose exec -u abc …`, then `sudo chown -R $USER: designs config*` |
| "port … already in use" | Another service is on 3000-3003 | Free the port, or change the host side of `ports:` in `docker-compose.yml` |
| A new `freecad` container fails because the name is taken | An old container from a different checkout | `docker rm -f freecad prusaslicer uvtools` (confirm with the user first) |

## Daily use, after setup
```bash
docker compose exec -u abc freecad /opt/freecad/usr/bin/freecadcmd /config/designs/<script>.py
docker compose exec -u abc freecad /config/designs/slice_ld002h.sh /config/designs/<model>.stl   # --help for options
```
Open the resulting `.ctb` in UVtools (`/config/designs`). Copy it to a USB stick for the printer.
