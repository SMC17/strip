"""L1 aero ranking for parametric wing / UAS (NeuralFoil when available).

Fidelity: L1 — suitable for offline design-search ranking of simple wings.
NOT FAA certification, NOT ARP6983 conformance, NOT flight-test validated,
NOT CREATE/VSPAERO panel solve (that would be L2).

When ``neuralfoil`` is installed, section CL/CD come from the ML surrogate at
the wing mean AoA and a Re based on MAC. Otherwise a thin-airfoil + parabolic
drag polar fallback is used and labeled explicitly.
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
    notes: str

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


def estimate_aero(
    w: WingState,
    *,
    u_mps: float = 25.0,
    prefer_neuralfoil: bool = True,
) -> AeroResult:
    """Return wing-level L1 aero rank metrics.

    Uses section aero + simple finite-wing corrections (Oswald e≈0.85,
    induced drag). Ranking only — not a VLM/panel prediction.
    """
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
        "Not FAA cert / not ARP6983 / not flight clearance / not VSPAERO."
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
        notes=notes,
    )


def drag_rank_index(w: WingState) -> float:
    """Scalar for reward: CD at design alpha (lower is better among peers)."""
    return estimate_aero(w).CD
