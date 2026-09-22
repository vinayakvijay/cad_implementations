FROM lscr.io/linuxserver/freecad:1.1.3

# CAD scripts and outputs are mounted at /config/designs (see docker-compose.yml)
WORKDIR /config/designs
