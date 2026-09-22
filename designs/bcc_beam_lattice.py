"""Generate a solid BCC (body-centered cubic) beam lattice in FreeCAD.

Defaults: 2x2x2 unit cells, 10 mm cell size, 1 mm beam diameter.
Run inside the container:
  docker compose exec freecad /opt/freecad/usr/bin/freecadcmd /config/designs/bcc_beam_lattice.py
"""

from __future__ import annotations

import os

import FreeCAD as App
import Mesh
import MeshPart
import Part

# --- parameters (edit these) ---
NX = 2
NY = 2
NZ = 2
CELL_SIZE = 10.0  # mm
BEAM_DIAMETER = 1.0  # mm

OUTPUT_DIR = os.path.dirname(os.path.abspath(__file__))
FCSTD_PATH = os.path.join(OUTPUT_DIR, "bcc_beam_lattice.FCStd")
STL_PATH = os.path.join(OUTPUT_DIR, "bcc_beam_lattice.stl")


def _corner_offsets(cell_size: float):
    half = 0.0
    full = cell_size
    return (
        (half, half, half),
        (full, half, half),
        (half, full, half),
        (full, full, half),
        (half, half, full),
        (full, half, full),
        (half, full, full),
        (full, full, full),
    )


def make_beam(p1: App.Vector, p2: App.Vector, radius: float) -> Part.Shape | None:
    direction = p2 - p1
    length = direction.Length
    if length < 1e-9:
        return None
    return Part.makeCylinder(radius, length, p1, direction)


def build_bcc_lattice(
    nx: int,
    ny: int,
    nz: int,
    cell_size: float,
    beam_diameter: float,
) -> Part.Shape:
    radius = beam_diameter / 2.0
    beams: list[Part.Shape] = []
    corners = _corner_offsets(cell_size)

    for ix in range(nx):
        for iy in range(ny):
            for iz in range(nz):
                origin = App.Vector(ix * cell_size, iy * cell_size, iz * cell_size)
                center = origin + App.Vector(cell_size / 2.0, cell_size / 2.0, cell_size / 2.0)
                for dx, dy, dz in corners:
                    corner = origin + App.Vector(dx, dy, dz)
                    beam = make_beam(corner, center, radius)
                    if beam is not None:
                        beams.append(beam)

    if not beams:
        raise RuntimeError("No beams generated; check NX/NY/NZ and CELL_SIZE.")

    solid = beams[0]
    for beam in beams[1:]:
        solid = solid.fuse(beam)

    solid = solid.removeSplitter()
    return solid


def main() -> None:
    doc = App.newDocument("BCCBeamLattice")
    shape = build_bcc_lattice(NX, NY, NZ, CELL_SIZE, BEAM_DIAMETER)
    obj = doc.addObject("Part::Feature", "BCC_Lattice")
    obj.Shape = shape
    doc.recompute()

    doc.saveAs(FCSTD_PATH)

    mesh = MeshPart.meshFromShape(
        Shape=shape,
        LinearDeflection=0.1,
        AngularDeflection=0.5,
        Relative=False,
    )
    mesh.write(STL_PATH)

    print(f"Cells: {NX} x {NY} x {NZ}")
    print(f"Cell size: {CELL_SIZE} mm")
    print(f"Beam diameter: {BEAM_DIAMETER} mm")
    print(f"Saved: {FCSTD_PATH}")
    print(f"Saved: {STL_PATH}")

    App.closeDocument(doc.Name)


main()
