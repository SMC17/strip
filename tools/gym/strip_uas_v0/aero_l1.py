"""L1 aero ranking for parametric wing / UAS.

Fidelity ladder (exploratory only):

* **NeuralFoil / analytic** — cheap section + induced-drag rank (default).
* **VSPAERO** — optional vortex-lattice CL/CD when OpenVSP CLI is present
  (``prefer_vspaero=True``). Used by DesignSearchEnv reward when enabled.

NOT FAA certification, NOT ARP6983 conformance, NOT flight-test validated.
VSPAERO here is L1 VLM ranking — not a cert panel case.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Any

from .wing import WingState

RHO_SL = 1.225  # kg/m^3 ISA SL
MU_SL = 1.789e-5  # Pa·s
NU_SL = MU_SL / RHO_SL
G = 9.80665


@dataclass
class AeroResult:
    CL: float
    CD: float
    CM: float | None
    LD: float
    Re_mac: float
    alpha_deg: float
    fidelity: str
    neuralfoil_used: bool
    vspaero_used: bool = False
    notes: str = ""

    def to_dict(self) -> dict[str, Any]:
        return {
            "CL": self.CL,
            "CD": self.CD,
            "CM": self.CM,
            "LD": self.LD,
            "Re_mac": self.Re_mac,
            "alpha_deg": self.alpha_deg,
            "fidelity": self.fidelity,
            "neuralfoil_used": self.neuralfoil_used,
            "vspaero_used": self.vspaero_used,
            "notes": self.notes,
        }


def _re_mac(w: WingState, u_mps: float = 25.0) -> float:
    return max(1e4, u_mps * w.mac_m() / NU_SL)


def _analytic_section(alpha_deg: float, tc: float) -> tuple[float, float, float | None]:
    """Thin-airfoil CL + parabolic CD (exploratory fallback)."""
    alpha = math.radians(alpha_deg)
    cl = 2.0 * math.pi * alpha  # thin airfoil
    # soft stall-ish clamp
    cl = max(-1.2, min(1.4, cl))
    cd0 = 0.006 + 0.8 * (tc - 0.12) ** 2
    k = 0.04 + 0.5 * abs(tc - 0.12)
    cd = cd0 + k * cl * cl
    return float(cl), float(max(cd, 1e-4)), None


def _neuralfoil_section(
    alpha_deg: float, re: float, tc: float
) -> tuple[float, float, float | None, bool, str]:
    """Try NeuralFoil; return (CL, CD, CM, used, fidelity_tag)."""
    try:
        from .teachers import neuralfoil_stub
    except Exception:
        cl, cd, cm = _analytic_section(alpha_deg, tc)
        return cl, cd, cm, False, "L1_analytic_polar"

    avail = neuralfoil_stub.detect()
    if not avail.available:
        cl, cd, cm = _analytic_section(alpha_deg, tc)
        return cl, cd, cm, False, "L1_analytic_polar"

    # Prefer NACA00xx-ish via default kulfan; thickness not fully mapped —
    # honesty: section surrogate at alpha/Re, not 3D wing solve.
    r = neuralfoil_stub.run(alpha_deg=alpha_deg, Re=re, model_size="small")
    if r.get("skipped") or r.get("CL") is None or r.get("CD") is None:
        cl, cd, cm = _analytic_section(alpha_deg, tc)
        return cl, cd, cm, False, "L1_analytic_polar"
    return (
        float(r["CL"]),
        float(max(r["CD"], 1e-5)),
        None if r.get("CM") is None else float(r["CM"]),
        True,
        "L1_neuralfoil_section",
    )


def _vspaero_wing(
    w: WingState,
    *,
    work_dir: str | None = None,
    timeout_sec: float = 120.0,
) -> AeroResult | None:
    """Try VSPAERO VLM for wing-level CL/CD; return None if skipped/failed."""
    try:
        from .teachers import vspaero_l1
    except Exception:
        return None

    avail = vspaero_l1.detect()
    if not avail.available:
        return None

    r = vspaero_l1.run_for_wing(
        w, availability=avail, work_dir=work_dir, timeout_sec=timeout_sec
    )
    if r.get("skipped") or r.get("CL") is None or r.get("CD") is None:
        return None

    cl = float(r["CL"])
    cd = float(max(r["CD"], 1e-9))
    cm = None if r.get("CM") is None else float(r["CM"])
    ld = cl / cd
    re = _re_mac(w)
    notes = (
        "VSPAERO vortex-lattice wing CL/CD (parametric). "
        "Exploratory L1 VLM rank — not FAA cert / not ARP6983 / not flight clearance."
    )
    return AeroResult(
        CL=cl,
        CD=cd,
        CM=cm,
        LD=float(ld),
        Re_mac=float(re),
        alpha_deg=float(w.alpha_deg),
        fidelity="L1_vspaero_vlm",
        neuralfoil_used=False,
        vspaero_used=True,
        notes=notes,
    )


def estimate_aero(
    w: WingState,
    *,
    u_mps: float = 25.0,
    prefer_neuralfoil: bool = True,
    prefer_vspaero: bool = False,
    vspaero_work_dir: str | None = None,
    vspaero_timeout_sec: float = 120.0,
) -> AeroResult:
    """Return wing-level L1 aero rank metrics.

    When ``prefer_vspaero`` is True and OpenVSP ``vspscript``+``vspaero`` are
    available, uses VSPAERO CL/CD directly (DesignSearchEnv reward path).
    Otherwise uses section aero + simple finite-wing corrections (NeuralFoil
    or analytic) — the cheap default L1 path.
    """
    if prefer_vspaero:
        vs = _vspaero_wing(
            w, work_dir=vspaero_work_dir, timeout_sec=vspaero_timeout_sec
        )
        if vs is not None:
            return vs
        # fall through cleanly — OpenVSP absent or script failed

    re = _re_mac(w, u_mps=u_mps)
    # Effective section AoA ≈ freestream + half tip twist (crude)
    alpha_eff = w.alpha_deg + 0.5 * w.twist_deg
    if prefer_neuralfoil:
        cl_sec, cd_sec, cm, nf_used, fid = _neuralfoil_section(alpha_eff, re, w.tc)
    else:
        cl_sec, cd_sec, cm = _analytic_section(alpha_eff, w.tc)
        nf_used, fid = False, "L1_analytic_polar"

    ar = max(w.aspect_ratio(), 1.0)
    # Simple sweep / taper knockdowns (exploratory)
    sweep_rad = math.radians(abs(w.sweep_deg))
    cl_wing = cl_sec * math.cos(sweep_rad) ** 2
    e = 0.85 - 0.05 * (1.0 - w.taper)  # taper mild effect
    e = max(0.6, min(0.95, e))
    cd_i = (cl_wing**2) / (math.pi * ar * e)
    cd_wing = cd_sec + cd_i
    ld = cl_wing / max(cd_wing, 1e-6)
    notes = (
        "Exploratory L1 wing rank (section + induced). "
        "Not FAA cert / not ARP6983 / not flight clearance."
    )
    if prefer_vspaero:
        notes = (
            "VSPAERO unavailable or skipped; fell back to cheap L1. " + notes
        )
    if nf_used:
        notes = "NeuralFoil section + induced-drag rank. " + notes
    else:
        notes = "Analytic polar fallback (neuralfoil absent or skipped). " + notes
    return AeroResult(
        CL=float(cl_wing),
        CD=float(cd_wing),
        CM=cm,
        LD=float(ld),
        Re_mac=float(re),
        alpha_deg=float(alpha_eff),
        fidelity=fid,
        neuralfoil_used=nf_used,
        vspaero_used=False,
        notes=notes,
    )


def drag_rank_index(w: WingState) -> float:
    """Scalar for reward: CD at design alpha (lower is better among peers)."""
    return estimate_aero(w).CD
