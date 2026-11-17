"""VSPAERO wing + horizontal-tail neutral point (``vspaero_wing_tail_v0``).

Independent cross-check of the analytic tail term in ``airframe.py``: the same
trapezoidal wing as ``vspaero_l1`` plus a rectangular horizontal tail (a second
OpenVSP WING geom: area, aspect ratio and aerodynamic-centre position taken from
an ``Airframe``), solved by VSPAERO (VLM) at two angles of attack. The neutral
point is ``x_np = −(dCMy/dα)/(dCL/dα)·c_ref`` with references from the wing
(``RefFlag`` = wing) and the moment reference at the wing-root leading edge.

The fuselage is **not** included (VSPAERO's thin-surface VLM does not give a
TR 711-comparable body moment), so this checks the wing + tail balance and the
tail's downwash / efficiency assumptions only. Tail height above the wing plane
is a parameter (default 0.1·span_t; the analytic model has no height effect).
Exploratory VLM; not certification, not FAA / ARP6983.
"""

from __future__ import annotations

import math
import subprocess
import tempfile
from pathlib import Path
from typing import Any

from . import vspaero_l1 as v1

LABEL = "vspaero_wing_tail_v0"

_TAIL_BLOCK = r"""
    string tail_id = AddGeom( "WING", "" );
    SetGeomName( tail_id, "HTail" );
    SetDriverGroup( tail_id, 1, AREA_WSECT_DRIVER, ROOTC_WSECT_DRIVER, TIPC_WSECT_DRIVER );
    SetParmVal( tail_id, "Root_Chord", "XSec_1", TAIL_CHORD_PLACEHOLDER );
    SetParmVal( tail_id, "Tip_Chord", "XSec_1", TAIL_CHORD_PLACEHOLDER );
    SetParmVal( tail_id, "Area", "XSec_1", TAIL_HALF_AREA_PLACEHOLDER );
    SetParmVal( tail_id, "Sweep", "XSec_1", 0.0 );
    SetParmVal( tail_id, "X_Rel_Location", "XForm", TAIL_X_PLACEHOLDER );
    SetParmVal( tail_id, "Z_Rel_Location", "XForm", TAIL_Z_PLACEHOLDER );
    SetParmVal( tail_id, "Tess_W", "Shape", 17 );
    SetParmVal( tail_id, "SectTess_U", "XSec_1", 6 );
    Update();
"""

_ANCHOR = 'SetParmVal( wing_id, "SectTess_U", "XSec_1", 8 );\n    Update();\n'


def _render(params: dict[str, float], tail: dict[str, float] | None) -> str:
    body = v1._render_script(params)
    if tail is not None:
        assert _ANCHOR in body, "vspaero_l1 template changed; update the tail anchor"
        blk = _TAIL_BLOCK
        for k, v in {"TAIL_CHORD_PLACEHOLDER": tail["chord"], "TAIL_HALF_AREA_PLACEHOLDER": 0.5 * tail["area"],
                     "TAIL_X_PLACEHOLDER": tail["x_le"], "TAIL_Z_PLACEHOLDER": tail["z"]}.items():
            blk = blk.replace(k, f"{v:.8f}")
        body = body.replace(_ANCHOR, _ANCHOR + blk)
    return body


def _run_one(vspscript: str, params: dict[str, float], tail: dict[str, float] | None,
             timeout: float) -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="strip_vsp_tail_") as td:
        work = Path(td)
        (work / "s.vspscript").write_text(_render(params, tail), encoding="utf-8")
        proc = subprocess.run([vspscript, "-script", "s.vspscript"], cwd=str(work), capture_output=True,
                              text=True, timeout=timeout, check=False, env=v1._env_with_vendor(vspscript))
        out = (proc.stdout or "") + (proc.stderr or "")
        m = v1.parse_markers(out)
        return {"CL": m["CL"], "CM": m["CM"], "ok": "strip_uas_vspaero_ok" in out}


def tail_geometry(af: Any, *, z_frac_span: float = 0.1) -> dict[str, float]:
    span_t = math.sqrt(af.tail_aspect * af.tail_area_m2)
    chord = af.tail_area_m2 / span_t
    return {"area": af.tail_area_m2, "span": span_t, "chord": chord,
            "x_le": af.tail_x_ac_m - 0.25 * chord, "z": z_frac_span * span_t}


def neutral_point(w: Any, af: Any = None, *, d_alpha: float = 4.0, z_frac_span: float = 0.1,
                  timeout: float = 180.0) -> dict[str, Any] | None:
    """VSPAERO x_np [m aft of root LE] for the wing alone (``af=None``) or wing + tail."""
    avail = v1.detect()
    if not avail.available:
        return None
    kw = dict(span_m=w.span_m, chord_root_m=w.chord_root_m, taper=w.taper, sweep_deg=w.sweep_deg,
              twist_deg=w.twist_deg)
    tail = tail_geometry(af, z_frac_span=z_frac_span) if af is not None and af.mode != "wing_only" else None
    res = []
    for a in (0.0, d_alpha):
        r = _run_one(avail.vspscript, v1._wing_params(alpha_deg=a, **kw), tail, timeout)
        if not r["ok"] or r["CL"] is None or r["CM"] is None:
            return None
        res.append(r)
    da = math.radians(d_alpha)
    cla = (res[1]["CL"] - res[0]["CL"]) / da
    cma = (res[1]["CM"] - res[0]["CM"]) / da
    return {"label": LABEL, "CL_alpha_per_rad": cla, "CM_alpha_per_rad": cma,
            "x_np_m": -cma / cla * w.mac_m(), "tail": tail, "backend": "vspaero"}
