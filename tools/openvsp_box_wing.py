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

    # Mirrors tools/openvsp_box_wing.vspscript (the pinned, CI-exercised path).
    # Planform parms live in "XSec_1", placement in "XForm"; under "Design" they
    # are silently ignored and the default wing is exported. Not exercised on
    # CI: the 3.42.0 Python bindings need libpython3.12.
    vsp.ClearVSPModel()
    fuse_id = vsp.AddGeom("FUSELAGE", "")
    vsp.SetParmVal(fuse_id, "Length", "Design", 8.0)

    for gid, half_span, chord, x, z in (
        (vsp.AddGeom("WING", ""), 5.0, 1.5, 2.0, None),
        (vsp.AddGeom("WING", ""), 1.5, 0.8, 7.0, 1.0),
    ):
        vsp.SetDriverGroup(gid, 1, vsp.SPAN_WSECT_DRIVER, vsp.ROOTC_WSECT_DRIVER, vsp.TIPC_WSECT_DRIVER)
        vsp.SetParmVal(gid, "Span", "XSec_1", half_span)
        vsp.SetParmVal(gid, "Root_Chord", "XSec_1", chord)
        vsp.SetParmVal(gid, "Tip_Chord", "XSec_1", chord)
        vsp.SetParmVal(gid, "Sweep", "XSec_1", 0.0)
        vsp.SetParmVal(gid, "X_Rel_Location", "XForm", x)
        if z is not None:
            vsp.SetParmVal(gid, "Z_Rel_Location", "XForm", z)

    vsp.Update()
    n_err = vsp.ErrorMgr.GetNumTotalErrors()
    if n_err:
        while vsp.ErrorMgr.GetNumTotalErrors() > 0:
            print(vsp.ErrorMgr.PopLastError().GetErrorString(), file=sys.stderr)
        print(f"OpenVSP reported {n_err} API error(s); refusing to export", file=sys.stderr)
        return 1
    vsp.ExportFile(output_path, vsp.SET_ALL, vsp.EXPORT_STL)
    if not os.path.isfile(output_path):
        print("OpenVSP export did not produce output", file=sys.stderr)
        return 1
    print(output_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
