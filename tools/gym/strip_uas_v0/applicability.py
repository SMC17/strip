"""Empirical validity envelope for the L1 section oracles (advisory only).

Derived from ``reports/validation/neuralfoil_polar_validation.json`` (NeuralFoil vs
Ladson NASA TM-4074 + UIUC LSAT measured polars; see ``validation.py``). A design
outside the envelope is still evaluated and still credited: these checks are
recorded in acceptance/evidence with ``advisory=True`` and never change
``passed`` or the reward. They say "no measured data backs this number", not
"this number is wrong".
"""

from __future__ import annotations

import json
from functools import lru_cache
from pathlib import Path
from typing import Any

REPORT = Path(__file__).resolve().parents[1] / "reports" / "validation" / "neuralfoil_polar_validation.json"

# Gym fidelity tag -> oracle id in the validation report.
FIDELITY_TO_ORACLE = {
    "L1_neuralfoil_section": "neuralfoil_small",
    "L1_analytic_polar": "analytic",
}
# The NeuralFoil gym path evaluates a NACA 4-digit section (camber at 0.4 c) at the design
# t/c and camber (aero_l1._neuralfoil_section). Its section model is backed by measured data
# only over the t/c and camber ranges of the measured sections in the report (`gym_section`).
GYM_SECTION_ORACLE = "gym_section"

# Used only if the committed report is missing (same numbers as the report).
_FALLBACK = {
    "neuralfoil_small": {"validated_Re_bands": [[2.0e5, 5.5e5], [1.0e6, 2.0e7]],
                         "validated_alpha_range": [-8.07, 17.24]},
    "analytic": {"validated_Re_bands": [], "validated_alpha_range": None},
}
_FALLBACK_TC_RANGE = [0.0340, 0.1831]
_FALLBACK_CAMBER_RANGE = [0.0, 0.0597]
_FALLBACK_CAMBER_POS_RANGE = [0.33, 0.52]


@lru_cache(maxsize=1)
def section_tc_range() -> list[float] | None:
    """t/c range of the measured symmetric sections the gym's NACA 00xx model was checked on."""
    try:
        rep = json.loads(REPORT.read_text())
        return rep["per_oracle"][GYM_SECTION_ORACLE].get("tc_range")
    except (OSError, KeyError, ValueError):
        return list(_FALLBACK_TC_RANGE)


@lru_cache(maxsize=1)
def section_camber_range() -> list[float] | None:
    try:
        rep = json.loads(REPORT.read_text())
        return rep["per_oracle"][GYM_SECTION_ORACLE].get("camber_range")
    except (OSError, KeyError, ValueError):
        return list(_FALLBACK_CAMBER_RANGE)


@lru_cache(maxsize=1)
def section_camber_pos_range() -> list[float] | None:
    """5-95 % range of max-camber position p over the measured cambered sections (`gym_section`)."""
    try:
        rep = json.loads(REPORT.read_text())
        return rep["per_oracle"][GYM_SECTION_ORACLE].get("camber_pos_p05_p95") or list(_FALLBACK_CAMBER_POS_RANGE)
    except (OSError, KeyError, ValueError):
        return list(_FALLBACK_CAMBER_POS_RANGE)


@lru_cache(maxsize=1)
def envelopes() -> dict[str, dict[str, Any]]:
    try:
        rep = json.loads(REPORT.read_text())
        return {k: dict(v.get("envelope") or {}) for k, v in rep["per_oracle"].items()}
    except (OSError, KeyError, ValueError):
        return dict(_FALLBACK)


def assess(aero: Any, wing: Any = None) -> dict[str, Any]:
    """Return {"oracle", "checks": [(name, ok, value, threshold, detail)], "source"}."""
    a = aero.to_dict() if hasattr(aero, "to_dict") else dict(aero or {})
    fid = a.get("fidelity")
    oracle = FIDELITY_TO_ORACLE.get(str(fid))
    checks: list[tuple[str, bool, Any, Any, str]] = []
    if oracle is None:
        checks.append(("section_oracle_validated", False, fid, "measured-polar validation",
                       "no measured-data validation for this fidelity in the repo (e.g. VSPAERO VLM)"))
        return {"oracle": None, "checks": checks, "source": str(REPORT.name)}
    env = envelopes().get(oracle) or {}
    bands = env.get("validated_Re_bands") or []
    re = a.get("Re_mac")
    in_band = re is not None and any(lo <= float(re) < hi for lo, hi in bands)
    checks.append(("Re_in_validated_band", in_band, re, bands or "none",
                   f"{oracle}: median |dCL|<=0.05 and median |E_CD|<=15% vs measured polars"))
    ar = env.get("validated_alpha_range")
    al = a.get("alpha_deg")
    checks.append(("alpha_in_validated_range", bool(ar) and al is not None and ar[0] <= float(al) <= ar[1],
                   al, ar or "none", "alpha range of attached measured points in validated bands"))
    if wing is not None and oracle == "neuralfoil_small":
        tc = float(getattr(wing, "tc", 0.12))
        rng = section_tc_range()
        checks.append(("section_tc_in_measured_range", bool(rng) and rng[0] <= tc <= rng[1], tc, rng or "none",
                       "gym NeuralFoil path uses a NACA 4-digit at the design t/c; measured sections cover this range"))
        cam = float(getattr(wing, "camber", 0.0))
        crng = section_camber_range()
        checks.append(("section_camber_in_measured_range", bool(crng) and crng[0] <= cam <= crng[1], cam, crng or "none",
                       "NACA 4-digit max camber; measured sections with this max camber back the section model"))
        if cam > 0.005:
            pos = float(getattr(wing, "camber_pos", 0.4))
            prng = section_camber_pos_range()
            checks.append(("section_camber_pos_in_measured_range", bool(prng) and prng[0] <= pos <= prng[1], pos,
                           prng or "none", "max-camber position inside the 5-95% p range of the measured cambered sections"))
    return {"oracle": oracle, "checks": checks, "source": str(REPORT.name)}
