"""Parametric wing / small-UAS state and L0 geometric feasibility."""

from __future__ import annotations

import math
from dataclasses import asdict, dataclass, field
from typing import Any

# Soft bands for exploratory fixed-wing UAS (L0 geometry only — not FAR/CS).
AR_MIN, AR_MAX = 4.0, 18.0
TAPER_MIN, TAPER_MAX = 0.35, 1.0
SWEEP_MIN, SWEEP_MAX = -5.0, 35.0  # deg, quarter-chord proxy
TC_MIN, TC_MAX = 0.08, 0.18
TWIST_MIN, TWIST_MAX = -8.0, 4.0  # deg washout(+) not required
ALPHA_MIN, ALPHA_MAX = -4.0, 12.0  # deg section / wing AoA for L1
SPAN_MIN_M, SPAN_MAX_M = 0.4, 8.0
CROOT_MIN_M, CROOT_MAX_M = 0.08, 1.2


@dataclass
class WingState:
    """Particulars for a single trapezoidal wing (reference UAS explore)."""

    span_m: float = 2.4
    chord_root_m: float = 0.30
    taper: float = 0.70
    sweep_deg: float = 5.0
    tc: float = 0.12  # thickness / chord
    twist_deg: float = -2.0  # tip geometric twist (washout negative)
    alpha_deg: float = 2.0  # freestream AoA for L1 section/wing rank

    def chord_tip_m(self) -> float:
        return self.chord_root_m * self.taper

    def mean_chord_m(self) -> float:
        return 0.5 * (self.chord_root_m + self.chord_tip_m())

    def area_m2(self) -> float:
        return self.span_m * self.mean_chord_m()

    def aspect_ratio(self) -> float:
        s = self.area_m2()
        if s <= 0:
            return 0.0
        return self.span_m**2 / s

    def mac_m(self) -> float:
        """Mean aerodynamic chord for trapezoidal wing."""
        cr, ct = self.chord_root_m, self.chord_tip_m()
        if cr + ct <= 0:
            return 0.0
        return (2.0 / 3.0) * (cr + ct - (cr * ct) / (cr + ct))

    def as_vector(self) -> list[float]:
        return [
            self.span_m,
            self.chord_root_m,
            self.taper,
            self.sweep_deg,
            self.tc,
            self.twist_deg,
            self.alpha_deg,
        ]

    @classmethod
    def from_vector(cls, v: list[float] | tuple[float, ...]) -> "WingState":
        return cls(
            span_m=float(v[0]),
            chord_root_m=float(v[1]),
            taper=float(v[2]),
            sweep_deg=float(v[3]),
            tc=float(v[4]),
            twist_deg=float(v[5]),
            alpha_deg=float(v[6]) if len(v) > 6 else 2.0,
        )

    def clamp_soft(self) -> "WingState":
        w = WingState(**asdict(self))
        w.span_m = max(SPAN_MIN_M * 0.8, min(SPAN_MAX_M * 1.1, w.span_m))
        w.chord_root_m = max(CROOT_MIN_M * 0.8, min(CROOT_MAX_M * 1.1, w.chord_root_m))
        w.taper = max(0.25, min(1.05, w.taper))
        w.sweep_deg = max(-8.0, min(40.0, w.sweep_deg))
        w.tc = max(0.06, min(0.22, w.tc))
        w.twist_deg = max(-10.0, min(6.0, w.twist_deg))
        w.alpha_deg = max(-6.0, min(14.0, w.alpha_deg))
        return w

    def to_dict(self) -> dict[str, Any]:
        return {
            **asdict(self),
            "chord_tip_m": self.chord_tip_m(),
            "mean_chord_m": self.mean_chord_m(),
            "area_m2": self.area_m2(),
            "aspect_ratio": self.aspect_ratio(),
            "mac_m": self.mac_m(),
        }


@dataclass
class L0Report:
    feasible: bool
    violations: list[str] = field(default_factory=list)
    metrics: dict[str, float] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        return {
            "feasible": self.feasible,
            "violations": list(self.violations),
            "metrics": dict(self.metrics),
        }


def evaluate_l0(w: WingState) -> L0Report:
    """Algebraic / geometric feasibility — reject before L1 aero rank."""
    vios: list[str] = []
    if w.span_m <= 0 or w.chord_root_m <= 0:
        vios.append("non_positive_particulars")
    if w.chord_tip_m() <= 0:
        vios.append("non_positive_tip_chord")
    if w.area_m2() <= 0:
        vios.append("non_positive_area")
    ar = w.aspect_ratio()
    if not (AR_MIN <= ar <= AR_MAX):
        vios.append(f"AR_out_of_band:{ar:.3f}")
    if not (TAPER_MIN <= w.taper <= TAPER_MAX):
        vios.append(f"taper_out_of_band:{w.taper:.3f}")
    if not (SWEEP_MIN <= w.sweep_deg <= SWEEP_MAX):
        vios.append(f"sweep_out_of_band:{w.sweep_deg:.2f}")
    if not (TC_MIN <= w.tc <= TC_MAX):
        vios.append(f"tc_out_of_band:{w.tc:.3f}")
    if not (TWIST_MIN <= w.twist_deg <= TWIST_MAX):
        vios.append(f"twist_out_of_band:{w.twist_deg:.2f}")
    if not (ALPHA_MIN <= w.alpha_deg <= ALPHA_MAX):
        vios.append(f"alpha_out_of_band:{w.alpha_deg:.2f}")
    if not (SPAN_MIN_M <= w.span_m <= SPAN_MAX_M):
        vios.append(f"span_out_of_band:{w.span_m:.3f}")
    if not (CROOT_MIN_M <= w.chord_root_m <= CROOT_MAX_M):
        vios.append(f"chord_root_out_of_band:{w.chord_root_m:.3f}")
    # Honesty envelope: high sweep + high AR is outside simple model intent
    if w.sweep_deg > 25.0 and ar > 12.0:
        vios.append("geometry_model_outside_envelope")
    # Spar-depth floor (structure.py: published loads/material, labelled cap conventions)
    tc_req = float("nan")
    if w.span_m > 0 and w.chord_root_m > 0:
        from .structure import spar_check

        sc = spar_check(w)
        tc_req = sc.tc_required
        if not sc.feasible:
            vios.append(f"tc_below_spar_depth_floor:{w.tc:.3f}<{tc_req:.3f}")
    metrics = {
        "aspect_ratio": ar,
        "taper": w.taper,
        "sweep_deg": w.sweep_deg,
        "tc": w.tc,
        "area_m2": w.area_m2(),
        "mac_m": w.mac_m(),
        "alpha_deg": w.alpha_deg,
        "tc_required_spar": tc_req,
    }
    return L0Report(feasible=len(vios) == 0, violations=vios, metrics=metrics)
