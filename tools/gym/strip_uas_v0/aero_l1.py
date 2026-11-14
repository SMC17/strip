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

import numpy as np
from typing import Any

from .wing import WingState

RHO_SL = 1.225  # kg/m^3 ISA SL
MU_SL = 1.789e-5  # Pa·s
NU_SL = MU_SL / RHO_SL
G = 9.80665

# Section thickness model for the NeuralFoil path: the design's w.tc selects a symmetric
# NACA 00xx section (exact Kulfan scaling, teachers.neuralfoil_stub.naca00_kulfan). Before
# this, every design was evaluated on NACA 0012 regardless of w.tc. The flag exists only so
# reports/validation/section_tc_impact can reproduce the old behaviour; do not toggle in training.
MAP_SECTION_TC = True
SECTION_MODEL = "naca4_at_design_tc_and_camber_p0.4"


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


# Analytic fallback (no NeuralFoil). Published bases:
# * section C_l: thin-airfoil theory, 2*pi*alpha (Anderson, Fundamentals of Aerodynamics §4.7);
#   the +-1.2/1.4 clamp is a convention (no stall model).
# * section C_d: component build-up, C_d0 = 2 * C_f * FF with the turbulent flat-plate
#   C_f = 0.455 / (log10 Re)^2.58 (Schlichting; Raymer, Aircraft Design, eq. 12.27) and the
#   wing form factor FF = 1 + 0.6/(x/c)_m * t/c + 100 (t/c)^4 (Raymer eq. 12.30) with
#   (x/c)_m = 0.3 (convention for NACA 4-digit-like sections). Fully turbulent (no laminar run),
#   no lift-dependent profile drag: both are stated limits, not tuned.
# * wing induced drag: C_Di = C_L^2 / (pi A e) with the theoretical Oswald factor of
#   Nita & Scholz (2012), based on Hoerner's taper function shifted for sweep:
#   e = 1 / (1 + f(lambda - d_lambda) A), f(l) = 0.0524 l^4 - 0.15 l^3 + 0.1659 l^2 - 0.0706 l + 0.0119,
#   d_lambda = -0.357 + 0.45 exp(-0.0375 phi_25[deg]). Wing alone: no fuselage / C_D0 / Mach
#   statistical corrections (those are aircraft-level).
XC_MAX_THICKNESS = 0.3


def skin_friction_turbulent(re: float) -> float:
    return 0.455 / math.log10(max(re, 1e4)) ** 2.58


def section_cd0_buildup(tc: float, re: float) -> float:
    ff = 1.0 + 0.6 / XC_MAX_THICKNESS * tc + 100.0 * tc**4
    return 2.0 * skin_friction_turbulent(re) * ff


def oswald_nita_scholz(aspect_ratio: float, taper: float, sweep25_deg: float) -> float:
    """Theoretical Oswald (span) efficiency, Nita & Scholz (2012), wing alone."""
    dl = -0.357 + 0.45 * math.exp(-0.0375 * sweep25_deg)
    x = taper - dl
    f = 0.0524 * x**4 - 0.15 * x**3 + 0.1659 * x**2 - 0.0706 * x + 0.0119
    return 1.0 / (1.0 + f * aspect_ratio)


def zero_lift_alpha_naca4(camber: float, p: float = 0.4) -> float:
    """Thin-airfoil zero-lift angle [rad] of the NACA 4-digit mean line (Anderson §4.8, eq. 4.61)."""
    if camber <= 0:
        return 0.0
    th = (np.arange(400) + 0.5) * math.pi / 400
    x = (1 - np.cos(th)) / 2
    dz = np.where(x < p, 2 * camber / p**2 * (p - x), 2 * camber / (1 - p) ** 2 * (p - x))
    return float(-np.sum(dz * (np.cos(th) - 1.0)) * (math.pi / 400) / math.pi)


def _analytic_section(alpha_deg: float, tc: float, re: float = 4.0e5, camber: float = 0.0) -> tuple[float, float, float | None]:
    """Thin-airfoil C_l (incl. NACA 4-digit camber) + build-up C_d0 (exploratory fallback; see bases above)."""
    alpha = math.radians(alpha_deg) - zero_lift_alpha_naca4(camber)
    cl = 2.0 * math.pi * alpha
    cl = max(-1.2, min(1.4, cl))
    return float(cl), float(section_cd0_buildup(tc, re)), None


def _neuralfoil_section(
    alpha_deg: float, re: float, tc: float, camber: float = 0.0
) -> tuple[float, float, float | None, bool, str]:
    """Try NeuralFoil; return (CL, CD, CM, used, fidelity_tag)."""
    try:
        from .teachers import neuralfoil_stub
    except Exception:
        cl, cd, cm = _analytic_section(alpha_deg, tc, re, camber)
        return cl, cd, cm, False, "L1_analytic_polar"

    avail = neuralfoil_stub.detect()
    if not avail.available:
        cl, cd, cm = _analytic_section(alpha_deg, tc, re, camber)
        return cl, cd, cm, False, "L1_analytic_polar"

    # Symmetric NACA 00xx at the design thickness (camber not modelled); section
    # surrogate at alpha/Re, not a 3-D wing solve.
    if MAP_SECTION_TC:
        kp = neuralfoil_stub.naca4_kulfan(tc, camber)
        name = f"naca4_m{camber:.4f}_p0.4_t{tc:.4f}"
    else:
        kp, name = None, "naca0012"
    r = neuralfoil_stub.run(alpha_deg=alpha_deg, Re=re, model_size="small", kulfan_parameters=kp, airfoil=name)
    if r.get("skipped") or r.get("CL") is None or r.get("CD") is None:
        cl, cd, cm = _analytic_section(alpha_deg, tc, re, camber)
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
        cl_sec, cd_sec, cm, nf_used, fid = _neuralfoil_section(alpha_eff, re, w.tc, w.camber)
    else:
        cl_sec, cd_sec, cm = _analytic_section(alpha_eff, w.tc, re, w.camber)
        nf_used, fid = False, "L1_analytic_polar"

    ar = max(w.aspect_ratio(), 1.0)
    # Simple sweep / taper knockdowns (exploratory)
    sweep_rad = math.radians(abs(w.sweep_deg))
    cl_wing = cl_sec * math.cos(sweep_rad) ** 2
    if nf_used:
        # NeuralFoil path keeps its historical span-efficiency convention (not a published
        # correlation); see reports/validation/analytic_fallback.md for the comparison.
        e = 0.85 - 0.05 * (1.0 - w.taper)
        e = max(0.6, min(0.95, e))
    else:
        e = oswald_nita_scholz(ar, w.taper, w.sweep_deg)
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
        notes = (f"NeuralFoil section (NACA 4-digit, camber {w.camber:.3f} at 0.4c, t/c {w.tc:.3f}) + induced-drag rank. "
                 if MAP_SECTION_TC else "NeuralFoil section (fixed NACA 0012) + induced-drag rank. ") + notes
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
