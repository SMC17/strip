"""Horizontal tail + fuselage contributions to the neutral point (``airframe_np_v0``).

Adds to the wing-alone VLM neutral point (``stability.py``) two textbook,
published empirical terms:

* **Horizontal tail** (lift-weighted aerodynamic-centre balance, e.g. Etkin &
  Reid; Nelson, *Flight Stability and Automatic Control*, ch. 2):
  ``x_np = (a_w·x_np,w + a_te·x_ac,t − c̄·Cmα_f) / (a_w + a_te)``,
  ``a_te = η·(S_t/S)·a_t·(1 − dε/dα)``.
  Tail lift slope from the DATCOM / Helmbold planform formula
  ``a_t = 2πA/(2 + sqrt(A²(1 + tan²Λ) + 4))``; downwash from the elliptic
  far-field approximation ``dε/dα = 2·a_w/(π·A_w)``; ``η = 0.9`` (the dynamic
  pressure ratio NACA TR 711 also uses).
* **Fuselage** destabilising moment, Gilruth & White, NACA Report 711 (1941):
  ``dCm_f/dα = K_f·w_f²·L_f/(S·c̄)`` per radian (eq. 1 balances
  ``S_w·d·dC_L/dα`` [per rad] against ``K_f·w_f²·L_f``), with ``K_f`` digitised by
  hand from TR 711 fig. 8 vs the wing-root quarter-chord position in % of body
  length (10–60 %, outside → clamped and flagged). Digitisation uncertainty ≈ ±0.05
  in ``K_f``; TR 711 itself warns the rearward values rest on few data.

Fuselage lift, tail-on-wing upwash, propeller / power effects, elevator and
trim drag are not modelled. Geometry defaults in ``Airframe.default_for`` are
**conventions** sized off the wing (tail volume ≈ 0.5, fuselage ≈ 0.6 span), not
a design. Not FAA / EASA, not a handling-qualities requirement.
"""

from __future__ import annotations

import math
from dataclasses import asdict, dataclass
from typing import Any

import numpy as np

from .wing import WingState

LABEL = "airframe_np_v0"
ETA_TAIL = 0.9
# NACA TR 711 fig. 8: (wing-root 1/4-chord position, % body length) -> K_f (hand-digitised)
TR711_KF = ((10.0, 0.07), (20.0, 0.30), (30.0, 0.59), (40.0, 1.00), (50.0, 1.63), (60.0, 2.70))
MODES = ("wing_only", "wing_tail", "wing_tail_fuselage")


def k_f(position_pct: float) -> tuple[float, bool]:
    xs, ys = zip(*TR711_KF)
    inside = xs[0] <= position_pct <= xs[-1]
    return float(np.interp(position_pct, xs, ys)), inside


def datcom_lift_slope(aspect: float, sweep_half_chord_deg: float = 0.0) -> float:
    t = math.tan(math.radians(sweep_half_chord_deg))
    return 2.0 * math.pi * aspect / (2.0 + math.sqrt(aspect**2 * (1.0 + t * t) + 4.0))


@dataclass(frozen=True)
class Airframe:
    """Tail and fuselage geometry, x measured aft of the wing-root leading edge [m]."""

    mode: str = "wing_tail_fuselage"
    tail_area_m2: float = 0.15
    tail_x_ac_m: float = 1.2  # tail aerodynamic centre
    tail_aspect: float = 4.0
    tail_sweep_deg: float = 0.0
    eta: float = ETA_TAIL
    fus_width_m: float = 0.12
    fus_length_m: float = 1.5
    fus_nose_x_m: float = -0.45  # nose position (negative = ahead of the wing-root LE)

    def __post_init__(self) -> None:
        if self.mode not in MODES:
            raise ValueError(f"mode must be one of {MODES}")

    @classmethod
    def default_for(cls, w: WingState, mode: str = "wing_tail_fuselage", *, tail_volume: float = 0.5,
                    tail_arm_mac: float = 3.0, fus_len_span: float = 0.6, fus_width_mac: float = 0.45,
                    wing_pos_frac: float = 0.30) -> "Airframe":
        """Convention sizing from the wing: S_t from the tail volume at the given arm."""
        from .vlm import mac_geometry

        mac, _, x_le_mac = mac_geometry(w)
        x_ac_w = x_le_mac + 0.25 * mac
        lt = tail_arm_mac * mac
        St = tail_volume * w.area_m2() * mac / lt
        L = fus_len_span * w.span_m
        return cls(mode=mode, tail_area_m2=St, tail_x_ac_m=x_ac_w + lt, tail_aspect=4.0,
                   fus_width_m=fus_width_mac * mac, fus_length_m=L, fus_nose_x_m=-wing_pos_frac * L)

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


def neutral_point(w: WingState, af: Airframe | None, wing_vlm: dict[str, Any] | None = None) -> dict[str, Any]:
    """Configuration neutral point [m aft of root LE] and the terms behind it."""
    from .vlm import solve as vlm_solve

    v = wing_vlm or vlm_solve(w)
    a_w, x_w, mac, S = v["CL_alpha_per_rad"], v["x_np_m"], v["mac_m"], v["area_m2"]
    out: dict[str, Any] = {"label": LABEL, "mode": "wing_only" if af is None else af.mode,
                           "x_np_wing_m": x_w, "CL_alpha_wing_per_rad": a_w, "mac_m": mac}
    if af is None or af.mode == "wing_only":
        return out | {"x_np_m": x_w, "CL_alpha_per_rad": a_w, "in_range": True}
    a_t = datcom_lift_slope(af.tail_aspect, af.tail_sweep_deg)
    deps = 2.0 * a_w / (math.pi * w.aspect_ratio())
    a_te = af.eta * (af.tail_area_m2 / S) * a_t * (1.0 - deps)
    cma_f, kf, kf_in, pos = 0.0, None, True, None
    if af.mode == "wing_tail_fuselage":
        pos = 100.0 * (0.25 * w.chord_root_m - af.fus_nose_x_m) / af.fus_length_m
        kf, kf_in = k_f(pos)
        cma_f = kf * af.fus_width_m**2 * af.fus_length_m / (S * mac)
    x_np = (a_w * x_w + a_te * af.tail_x_ac_m - mac * cma_f) / (a_w + a_te)
    vh = af.tail_area_m2 * (af.tail_x_ac_m - (v["x_le_mac_m"] + 0.25 * mac)) / (S * mac)
    return out | {
        "x_np_m": x_np, "CL_alpha_per_rad": a_w + a_te, "tail_CL_alpha_per_rad": a_t,
        "downwash_gradient": deps, "tail_effective_slope_per_rad": a_te, "tail_volume": vh,
        "fuselage_Cm_alpha_per_rad": cma_f, "K_f": kf, "wing_quarter_chord_pct_body": pos,
        "in_range": kf_in, "airframe": af.to_dict(),
        "np_shift_tail_mac": (a_w * x_w + a_te * af.tail_x_ac_m) / (a_w + a_te) / mac - x_w / mac,
        "np_shift_fuselage_mac": -cma_f / (a_w + a_te),
        "sources": ["Etkin & Reid / Nelson tail-wing NP balance", "DATCOM/Helmbold lift slope",
                    "elliptic downwash 2a/(piA)", "NACA TR 711 (Gilruth & White 1941) eq. 1, fig. 8"],
    }


def resolve(af: Any, parent: WingState) -> Airframe | None:
    """``None`` | ``Airframe`` | mode string (sized off ``parent`` by convention)."""
    if af is None or isinstance(af, Airframe):
        return af
    if af == "wing_only":
        return None
    return Airframe.default_for(parent, str(af))
