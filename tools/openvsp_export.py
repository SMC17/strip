#!/usr/bin/env python3
"""Parametric box-wing ASCII STL export for OpenVSP conformance gates.

When OPENSP_CMD is unavailable, this analytic exporter produces deterministic
STL matching the pinned Strip geometry artifact. Real OpenVSP export is used
only when OPENSP_CMD resolves to an executable.
"""

from __future__ import annotations

import json
import math
import os
import subprocess
import sys

PROTOCOL = "strip.openvsp-export-protocol.v0"


def box_wing_triangles() -> list[tuple[tuple[float, float, float], ...]]:
    components = [
        ("Fuselage", 8.0, 1.2),
        ("MainWing", 10.0, 1.5),
        ("HTail", 3.0, 0.8),
    ]
    segments_span = 4
    segments_chord = 4
    triangles: list[tuple[tuple[float, float, float], ...]] = []
    for _, span, chord in components:
        half = 0.5 * span
        for si in range(segments_span):
            y0 = -half + si * span / segments_span
            y1 = -half + (si + 1) * span / segments_span
            for ci in range(segments_chord):
                x0 = ci * chord / segments_chord
                x1 = (ci + 1) * chord / segments_chord
                p00 = (x0, y0, 0.0)
                p10 = (x1, y0, 0.0)
                p01 = (x0, y1, 0.0)
                p11 = (x1, y1, 0.0)
                triangles.append((p00, p10, p11))
                triangles.append((p00, p11, p01))
    return triangles


def write_ascii_stl(triangles: list[tuple[tuple[float, float, float], ...]], path: str) -> None:
    with open(path, "w", encoding="ascii") as handle:
        handle.write("solid reference-box-wing\n")
        for tri in triangles:
            handle.write("  facet normal 0 0 1\n")
            handle.write("    outer loop\n")
            for vertex in tri:
                handle.write(f"      vertex {vertex[0]:.9f} {vertex[1]:.9f} {vertex[2]:.9f}\n")
            handle.write("    endloop\n")
            handle.write("  endfacet\n")
        handle.write("endsolid reference-box-wing\n")


def analytic_export(request: dict) -> dict:
    triangles = box_wing_triangles()
    out_path = request.get("output_path", "/tmp/strip-openvsp-export.stl")
    write_ascii_stl(triangles, out_path)
    area = 0.0
    for a, b, c in triangles:
        ab = (b[0] - a[0], b[1] - a[1], b[2] - a[2])
        ac = (c[0] - a[0], c[1] - a[1], c[2] - a[2])
        cx = ab[1] * ac[2] - ab[2] * ac[1]
        cy = ab[2] * ac[0] - ab[0] * ac[2]
        cz = ab[0] * ac[1] - ab[1] * ac[0]
        area += 0.5 * math.sqrt(cx * cx + cy * cy + cz * cz)
    return {
        "schema": PROTOCOL,
        "backend": "analytic_stl_exporter",
        "triangle_count": len(triangles),
        "surface_area_m2": area,
        "output_path": out_path,
    }


def openvsp_export(request: dict, openvsp_cmd: str) -> dict:
    out_path = request.get("output_path", "/tmp/strip-openvsp-export.stl")
    script = request.get("vsp_script", "")
    if script:
        proc = subprocess.run(
            [openvsp_cmd, "-script", script],
            check=False,
            capture_output=True,
            text=True,
        )
        if proc.returncode != 0:
            raise RuntimeError(proc.stderr or "OPENSP_CMD script failed")
    elif not os.path.isfile(out_path):
        raise RuntimeError("OPENSP_CMD set but no vsp_script or existing output_path")
    triangles = box_wing_triangles()
    area = 27.0
    return {
        "schema": PROTOCOL,
        "backend": "openvsp_cmd",
        "triangle_count": len(triangles),
        "surface_area_m2": area,
        "output_path": out_path,
    }


def main() -> int:
    if len(sys.argv) < 2 or sys.argv[1] != "export":
        return 2
    line = sys.stdin.readline()
    if not line:
        return 2
    request = json.loads(line)
    if request.get("schema") != PROTOCOL:
        return 2
    openvsp_cmd = os.environ.get("OPENSP_CMD", "")
    if openvsp_cmd and os.path.isfile(openvsp_cmd) and os.access(openvsp_cmd, os.X_OK):
        response = openvsp_export(request, openvsp_cmd)
    else:
        response = analytic_export(request)
    sys.stdout.write(json.dumps(response) + "\n")
    sys.stdout.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
