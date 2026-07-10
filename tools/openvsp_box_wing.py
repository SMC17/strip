#!/usr/bin/env python3
"""Build a minimal box-wing model in OpenVSP and export ASCII STL."""

from __future__ import annotations

import os
import sys


def main() -> int:
    output_path = os.environ.get("STRIP_OPENSP_OUTPUT", "/tmp/strip-openvsp-export.stl")
    try:
        import openvsp as vsp
    except ImportError as exc:
        print(f"openvsp python module unavailable: {exc}", file=sys.stderr)
        return 1

    vsp.ClearVSPModel()
    fuse_id = vsp.AddGeom("FUSELAGE", "")
    vsp.SetParmVal(fuse_id, "Length", "Design", 8.0)
    vsp.SetParmVal(fuse_id, "Width", "Design", 1.2)
    vsp.SetParmVal(fuse_id, "Height", "Design", 1.2)

    wing_id = vsp.AddGeom("WING", "")
    vsp.SetParmVal(wing_id, "Span", "Design", 10.0)
    vsp.SetParmVal(wing_id, "Root_Chord", "Design", 1.5)
    vsp.SetParmVal(wing_id, "Tip_Chord", "Design", 1.5)
    vsp.SetParmVal(wing_id, "X_Rel_Location", "Design", 2.0)

    tail_id = vsp.AddGeom("WING", "")
    vsp.SetParmVal(tail_id, "Span", "Design", 3.0)
    vsp.SetParmVal(tail_id, "Root_Chord", "Design", 0.8)
    vsp.SetParmVal(tail_id, "Tip_Chord", "Design", 0.8)
    vsp.SetParmVal(tail_id, "X_Rel_Location", "Design", 7.0)
    vsp.SetParmVal(tail_id, "Z_Rel_Location", "Design", 1.0)

    vsp.Update()
    vsp.ExportFile(output_path, vsp.SET_ALL, vsp.EXPORT_STL)
    if not os.path.isfile(output_path):
        print("OpenVSP export did not produce output", file=sys.stderr)
        return 1
    print(output_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
