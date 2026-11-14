"""Spar-depth floor: minimum t/c for the root bending moment (published bases + labelled conventions).

Load (published values, applied to a small UAS *by convention*):
* limit load factor n = 3.8 — 14 CFR 23.337(a)(1) normal category (pre-Amendment 64; the formula
  2.1 + 24000/(W+10000) caps at 3.8 for light aircraft);
* factor of safety 1.5 — 14 CFR 23.303, so n_ult = 5.7;
* elliptic span loading: each semi-span carries W/2 at a centroid 4/(3*pi) * b/2 from the root.

Section (conventions, labelled):
* two spar caps of width ``CAP_WIDTH_FRAC`` * c_root at the root, each at most ``CAP_DEPTH_FRAC``
  of the available depth h = ``DEPTH_EFF`` * (t/c) * c_root, cap centroids 0.8 h apart;
  so M <= sigma * (w * 0.2 h) * 0.8 h = 0.16 sigma w h^2.

Material (published): Sitka spruce, compression parallel to grain, 12 % MC: 38.7 MPa
(USDA FPL Wood Handbook, FPL-GTR-190, 2010, Table 5-3a). Wood caps are the conservative
small-UAS case; a carbon spar raises the allowable ~20x and the floor drops ~4.5x.

Mass: 5 kg, the same convention as ``mission.Mission``. Not FAA / ASTM conformance; an
exploratory feasibility floor only.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Any

from .wing import WingState

G = 9.80665
N_LIMIT = 3.8  # 14 CFR 23.337(a)(1)
FACTOR_OF_SAFETY = 1.5  # 14 CFR 23.303
MATERIALS = {"sitka_spruce": 38.7e6}  # Pa, Wood Handbook FPL-GTR-190 Table 5-3a
CAP_WIDTH_FRAC = 0.15  # convention
CAP_DEPTH_FRAC = 0.20  # convention
DEPTH_EFF = 0.85  # convention: usable depth / max section thickness at the spar
MASS_KG = 5.0  # convention (mission.Mission default)


@dataclass(frozen=True)
class SparCheck:
    root_moment_nm: float
    depth_required_m: float
    tc_required: float
    tc: float
    feasible: bool

    def to_dict(self) -> dict[str, Any]:
        return {"root_moment_nm": self.root_moment_nm, "depth_required_m": self.depth_required_m,
                "tc_required": self.tc_required, "tc": self.tc, "feasible": self.feasible,
                "basis": "14 CFR 23.337/23.303 loads (convention for UAS); elliptic loading; Wood Handbook spruce; cap geometry convention"}


def root_bending_moment(w: WingState, mass_kg: float = MASS_KG) -> float:
    n_ult = N_LIMIT * FACTOR_OF_SAFETY
    return n_ult * (mass_kg * G / 2.0) * (4.0 / (3.0 * math.pi)) * (w.span_m / 2.0)


def spar_check(w: WingState, mass_kg: float = MASS_KG, material: str = "sitka_spruce") -> SparCheck:
    m = root_bending_moment(w, mass_kg)
    sigma = MATERIALS[material]
    width = CAP_WIDTH_FRAC * w.chord_root_m
    k = CAP_DEPTH_FRAC * (1.0 - CAP_DEPTH_FRAC)  # 0.16
    h_req = math.sqrt(m / (k * sigma * max(width, 1e-6)))
    tc_req = h_req / (DEPTH_EFF * max(w.chord_root_m, 1e-6))
    return SparCheck(m, h_req, tc_req, w.tc, w.tc >= tc_req)
