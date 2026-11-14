"""Wing-alone longitudinal static stability: neutral point and static margin (``static_margin_v0``).

Neutral point from the in-repo planar VLM (``vlm.py``), optionally cross-checked
against VSPAERO (two-alpha CMy slope) when OpenVSP is installed.

Static margin ``SM = (x_np - x_cg) / MAC``. The CG is a **convention**:

* ``cg_mode="fixed"``: absolute ``x_cg`` (m aft of the root leading edge) —
  e.g. inherited from the parent design, so a child that moves its wing's
  neutral point relative to a fixed payload/fuselage CG changes its margin.
* ``cg_mode="frac_mac"``: CG at ``cg_frac_mac`` of the MAC from the MAC leading edge.

Scope: **wing alone** by default; pass ``airframe=airframe.Airframe(...)`` for
the horizontal-tail and NACA TR 711 fuselage terms (``airframe.py``; modes
``wing_only`` / ``wing_tail`` / ``wing_tail_fuselage``). No propeller or
control-surface effects; planar flat-plate VLM (linear, inviscid). The static-margin band is a
user convention, not a handling-qualities requirement; trim (Cm about the CG
at the cruise CL) is reported but not gated, because a wing-alone trim needs
reflex / washout that this model only partly captures. Not FAA / EASA, not
ARP6983 / ED-324, not flight-test validated.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Any

from .acceptance import AcceptanceResult, Check
from .vlm import solve as vlm_solve
from .wing import WingState

LABEL = "static_margin_v0"
SM_BAND_CONVENTION = (0.05, 0.30)
DEFAULT_CG_FRAC_MAC = 0.15
VSP_NP_TOL_MAC = 0.08  # VLM vs VSPAERO neutral-point agreement band (fraction of MAC)


@dataclass(frozen=True)
class CG:
    mode: str = "frac_mac"  # "frac_mac" | "fixed"
    value: float = DEFAULT_CG_FRAC_MAC

    def x_cg(self, v: dict[str, Any]) -> float:
        if self.mode == "fixed":
            return float(self.value)
        if self.mode == "frac_mac":
            return v["x_le_mac_m"] + float(self.value) * v["mac_m"]
        raise ValueError("cg mode must be 'frac_mac' or 'fixed'")

    def to_dict(self) -> dict[str, Any]:
        return {"mode": self.mode, "value": self.value}


def cg_for_margin(w: WingState, sm_target: float = 0.10, *, airframe: Any = None) -> CG:
    """Fixed CG that gives ``w`` the target static margin (use on the parent, then hold it)."""
    from .airframe import neutral_point

    v = vlm_solve(w)
    return CG("fixed", neutral_point(w, airframe, v)["x_np_m"] - sm_target * v["mac_m"])


def vspaero_neutral_point(w: WingState, *, d_alpha: float = 4.0) -> dict[str, Any] | None:
    """Two-alpha VSPAERO CL/CMy slope → x_np (moment reference at the root LE origin)."""
    from .teachers import vspaero_l1

    if not vspaero_l1.detect().available:
        return None
    kw = dict(span_m=w.span_m, chord_root_m=w.chord_root_m, taper=w.taper,
              sweep_deg=w.sweep_deg, twist_deg=w.twist_deg)
    r0 = vspaero_l1.run(alpha_deg=0.0, **kw)
    r1 = vspaero_l1.run(alpha_deg=d_alpha, **kw)
    if any(r.get("skipped") or r.get("CL") is None or r.get("CM") is None for r in (r0, r1)):
        return None
    da = math.radians(d_alpha)
    cla = (float(r1["CL"]) - float(r0["CL"])) / da
    cma = (float(r1["CM"]) - float(r0["CM"])) / da
    if abs(cla) < 1e-9:
        return None
    return {"CL_alpha_per_rad": cla, "x_np_m": -cma / cla * w.mac_m(), "backend": "vspaero"}


def static_margin(w: WingState, cg: CG = CG(), *, cl_cruise: float | None = None,
                  cross_check_vspaero: bool = False, airframe: Any = None) -> dict[str, Any]:
    from .airframe import neutral_point

    v = vlm_solve(w)
    x_cg = cg.x_cg(v)
    npc = neutral_point(w, airframe, v)
    sm = (npc["x_np_m"] - x_cg) / v["mac_m"]
    wing_only = npc["mode"] == "wing_only"
    out: dict[str, Any] = {
        "label": LABEL, "x_np_m": npc["x_np_m"], "np_frac_mac": (npc["x_np_m"] - v["x_le_mac_m"]) / v["mac_m"],
        "x_cg_m": x_cg, "cg": cg.to_dict(), "static_margin": sm, "mac_m": v["mac_m"],
        "CL_alpha_per_rad": npc["CL_alpha_per_rad"], "backend": "vlm_planar_v0",
        "configuration": npc["mode"], "x_np_wing_m": v["x_np_m"],
        "static_margin_wing_only": (v["x_np_m"] - x_cg) / v["mac_m"],
        "notes": ("Wing alone (no tail/fuselage)" if wing_only else
                  "Wing VLM + empirical tail / TR 711 fuselage terms (airframe.py)")
                 + "; CG is a convention; not a handling-qualities requirement.",
    }
    if not wing_only:
        out["airframe_terms"] = {k: npc[k] for k in npc if k not in ("label",)}
    if cl_cruise is not None and wing_only:
        # Cm about the CG at the cruise CL: CM_cg = CM0_ref + CL·(x_cg - x_ref)/MAC, from the VLM at α=0
        v0 = vlm_solve(w, 0.0, x_ref=x_cg)
        cm_cg = v0["CM"] + (cl_cruise - v0["CL"]) * (-sm)
        out["trim"] = {"CL": cl_cruise, "CM_cg": cm_cg, "gated": False}
    if cross_check_vspaero and wing_only:
        vs = vspaero_neutral_point(w)
        out["vspaero"] = vs
        if vs is not None:
            out["np_disagreement_frac_mac"] = abs(vs["x_np_m"] - v["x_np_m"]) / v["mac_m"]
    return out


def accept_stability(stab: dict[str, Any], *, band: tuple[float, float] = SM_BAND_CONVENTION,
                     np_tol_mac: float = VSP_NP_TOL_MAC) -> AcceptanceResult:
    res = AcceptanceResult(oracle=f"{LABEL}:{stab.get('backend')}")
    sm = stab.get("static_margin")
    ok = sm is not None and math.isfinite(float(sm))
    res.checks.append(Check("static_margin_finite", ok, sm))
    res.checks.append(Check("static_margin_in_band", ok and band[0] <= float(sm) <= band[1], sm,
                            f"{band[0]}-{band[1]}",
                            f"convention band; {stab.get('configuration', 'wing_only')}; CG convention"))
    terms = stab.get("airframe_terms") or {}
    if "in_range" in terms and terms.get("K_f") is not None:
        res.checks.append(Check("tr711_kf_in_digitised_range", bool(terms["in_range"]),
                                terms.get("wing_quarter_chord_pct_body"), "10-60 % body length",
                                "NACA TR 711 fig. 8 range"))
    if stab.get("np_disagreement_frac_mac") is not None:
        d = float(stab["np_disagreement_frac_mac"])
        res.checks.append(Check("np_vlm_vs_vspaero_agree", d <= np_tol_mac, d, np_tol_mac,
                                "two independent VLM implementations"))
    return res


def merge_acceptance(aero_acc: dict[str, Any], stab_acc: AcceptanceResult) -> dict[str, Any]:
    """Fold stability checks into an aero acceptance dict (same schema)."""
    out = dict(aero_acc)
    extra = [c.to_dict() | {"name": f"stability:{c.name}"} for c in stab_acc.checks]
    out["checks"] = list(aero_acc.get("checks", [])) + extra
    out["failed_checks"] = list(aero_acc.get("failed_checks", [])) + [
        f"stability:{n}" for n in stab_acc.failed_checks]
    out["passed"] = bool(aero_acc.get("passed")) and stab_acc.passed
    return out
