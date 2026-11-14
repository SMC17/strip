#!/usr/bin/env python3
"""Parametric box-wing ASCII STL export for OpenVSP conformance gates.

When OPENSP_CMD is unavailable, this analytic exporter produces deterministic
STL matching the pinned Strip geometry artifact. Real OpenVSP export is used
only when OPENSP_CMD resolves to an executable.
"""

from __future__ import annotations

import hashlib
import json
import math
import os
import subprocess
import sys
import tempfile

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


def triangle_area(a, b, c) -> float:
    ab = (b[0] - a[0], b[1] - a[1], b[2] - a[2])
    ac = (c[0] - a[0], c[1] - a[1], c[2] - a[2])
    cx = ab[1] * ac[2] - ab[2] * ac[1]
    cy = ab[2] * ac[0] - ab[0] * ac[2]
    cz = ab[0] * ac[1] - ab[1] * ac[0]
    return 0.5 * math.sqrt(cx * cx + cy * cy + cz * cz)


def parse_ascii_stl(path: str) -> tuple[list[tuple[tuple[float, float, float], ...]], float, str]:
    triangles: list[tuple[tuple[float, float, float], ...]] = []
    current: list[tuple[float, float, float]] = []
    canonical_parts: list[str] = []
    with open(path, encoding="ascii", errors="ignore") as handle:
        for raw in handle:
            line = raw.strip()
            if line.startswith("vertex"):
                parts = line.split()
                if len(parts) >= 4:
                    vertex = (float(parts[1]), float(parts[2]), float(parts[3]))
                    current.append(vertex)
                    canonical_parts.append(f"{vertex[0]:.9f}|{vertex[1]:.9f}|{vertex[2]:.9f}|")
                    if len(current) == 3:
                        triangles.append((current[0], current[1], current[2]))
                        current = []
    area = sum(triangle_area(*tri) for tri in triangles)
    digest = hashlib.sha256("".join(canonical_parts).encode("ascii")).hexdigest()
    return triangles, area, digest


def mesh_metrics(path: str) -> dict:
    triangles, area, digest = parse_ascii_stl(path)
    return {
        "triangle_count": len(triangles),
        "surface_area_m2": area,
        "mesh_digest": f"sha256:{digest}",
    }


def analytic_export(request: dict) -> dict:
    triangles = box_wing_triangles()
    out_path = request.get("output_path", "/tmp/strip-openvsp-export.stl")
    write_ascii_stl(triangles, out_path)
    metrics = mesh_metrics(out_path)
    return {
        "schema": PROTOCOL,
        "backend": "analytic_stl_exporter",
        "triangle_count": metrics["triangle_count"],
        "surface_area_m2": metrics["surface_area_m2"],
        "mesh_digest": metrics["mesh_digest"],
        "output_path": out_path,
    }


def openvsp_export(request: dict, openvsp_cmd: str) -> dict:
    out_path = os.path.abspath(request.get("output_path", "/tmp/strip-openvsp-export.stl"))
    if os.path.isfile(out_path):
        os.remove(out_path)
    # vspscript 3.42 segfaults (exit -11) instead of reporting a missing output dir.
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    script_dir = os.path.dirname(os.path.abspath(__file__))
    template_path = os.path.join(script_dir, "openvsp_box_wing.vspscript")
    with open(template_path, encoding="ascii") as handle:
        script_body = handle.read()
    script_body = script_body.replace("__OUTPUT_PATH__", out_path.replace("\\", "/"))
    env = os.environ.copy()
    # The rendered script goes in a private temp dir, not next to the STL (which
    # is often the repo root), so a run leaves only the requested output behind.
    with tempfile.TemporaryDirectory(prefix="strip_vsp_") as tmp:
        script_path = os.path.join(tmp, "box_wing.vspscript")
        with open(script_path, "w", encoding="ascii") as handle:
            handle.write(script_body)
        command = [openvsp_cmd, "-script", script_path]
        if not env.get("DISPLAY") and os.path.isfile("/usr/bin/xvfb-run"):
            command = ["xvfb-run", "-a", openvsp_cmd, "-script", script_path]
        proc = subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
            env=env,
            timeout=180,
        )
    # P0.3: nonzero vsp exit is always a failure — never accept a stale/partial STL.
    if proc.returncode != 0:
        detail = (proc.stderr or proc.stdout or "").strip()
        raise RuntimeError(
            f"OPENSP_CMD exited {proc.returncode}"
            + (f": {detail}" if detail else "")
        )
    if not os.path.isfile(out_path):
        raise RuntimeError("OPENSP_CMD export did not produce STL output")
    # OpenVSP reports bad parm names / groups as API errors but keeps going and
    # exports the *default* geometry. Treat any API error as a failed export.
    combined = (proc.stdout or "") + "\n" + (proc.stderr or "")
    api_errors = [ln.strip() for ln in combined.splitlines() if "Error Code:" in ln or "strip_vsp_api_error:" in ln]
    if api_errors:
        raise RuntimeError(
            f"OpenVSP script reported {len(api_errors)} API error(s); first: {api_errors[0]}"
        )
    if "strip_vsp_export_ok" not in combined:
        raise RuntimeError("OpenVSP script did not reach strip_vsp_export_ok (template mismatch?)")
    metrics = mesh_metrics(out_path)
    return {
        "schema": PROTOCOL,
        "backend": "openvsp_cmd",
        "triangle_count": metrics["triangle_count"],
        "surface_area_m2": metrics["surface_area_m2"],
        "mesh_digest": metrics["mesh_digest"],
        "output_path": out_path,
        "export_runtime_version": os.environ.get("OPENSP_RUNTIME_VERSION", "unknown"),
    }


def main() -> int:
    try:
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
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
