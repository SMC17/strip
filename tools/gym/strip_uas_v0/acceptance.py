"""Per-oracle acceptance gates for Strip-UAS-v0 (mirrors Yard-Sea-v0).

Every aero number is returned with an ``acceptance`` block. Reward and
"improved" claims credit the number only when ``acceptance["passed"]``.

Checks are harness-level (finite, inside the L1 model's stated envelope,
same fidelity as the parent it is compared to). They are NOT FAA AI
assurance, NOT ARP6983 / ED-324 conformance, NOT flight clearance.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import Any, Mapping

ACCEPTANCE_SCHEMA = "strip_uas_v0.acceptance.v1"

# Analytic polar clamps CL to [-1.2, 1.4]; hitting the clamp means the number is
# a stall-proxy artefact, not a lift prediction.
CL_CLAMP = (-1.2, 1.4)
ALPHA_EFF_RANGE = (-6.0, 12.0)  # deg, L1 attached-flow band (wing.py ALPHA band ± twist/2)
RE_RANGE = (1e4, 1e8)
CD_RANGE = (1e-4, 0.5)


@dataclass
class Check:
    name: str
    passed: bool
    value: float | str | None = None
    threshold: float | str | None = None
    detail: str = ""

    def to_dict(self) -> dict[str, Any]:
        v = self.value
        if isinstance(v, float) and not math.isfinite(v):
            v = None
        return {"name": self.name, "passed": bool(self.passed), "value": v,
                "threshold": self.threshold, "detail": self.detail}


@dataclass
class AcceptanceResult:
    oracle: str
    checks: list[Check] = field(default_factory=list)

    @property
    def passed(self) -> bool:
        return bool(self.checks) and all(c.passed for c in self.checks)

    @property
    def failed_checks(self) -> list[str]:
        return [c.name for c in self.checks if not c.passed]

    def to_dict(self) -> dict[str, Any]:
        return {
            "schema": ACCEPTANCE_SCHEMA,
            "oracle": self.oracle,
            "passed": self.passed,
            "failed_checks": self.failed_checks,
            "checks": [c.to_dict() for c in self.checks],
            "notes": "Harness acceptance only; not FAA AI assurance / not ARP6983 / not flight clearance.",
        }


def _finite(x: Any) -> bool:
    try:
        return x is not None and math.isfinite(float(x))
    except (TypeError, ValueError):
        return False


def is_accepted(result: Mapping[str, Any] | None) -> bool:
    if not result:
        return False
    acc = result.get("acceptance")
    return isinstance(acc, Mapping) and acc.get("passed") is True


def accept_aero(aero: Any, *, parent_fidelity: str | None = None) -> AcceptanceResult:
    """L1 / VSPAERO aero acceptance.

    ``parent_fidelity``: when given, the child must have been evaluated at the
    same fidelity. A VSPAERO parent compared with an analytic-fallback child is a
    silent mixed-fidelity comparison and is rejected.
    """
    a = aero.to_dict() if hasattr(aero, "to_dict") else dict(aero or {})
    res = AcceptanceResult(oracle=str(a.get("fidelity", "L1")))
    for k in ("CL", "CD", "LD"):
        res.checks.append(Check(f"{k}_finite", _finite(a.get(k)), a.get(k)))
    cd = a.get("CD")
    lo, hi = CD_RANGE
    res.checks.append(Check("CD_plausible", _finite(cd) and lo <= float(cd) <= hi, cd, f"{lo}-{hi}"))
    cl = a.get("CL")
    if a.get("fidelity") == "L1_analytic_polar":
        res.checks.append(
            Check("CL_not_clamped", _finite(cl) and CL_CLAMP[0] < float(cl) < CL_CLAMP[1], cl,
                  f"{CL_CLAMP}", "analytic polar clamp reached = stall proxy, not a prediction")
        )
    al = a.get("alpha_deg")
    alo, ahi = ALPHA_EFF_RANGE
    res.checks.append(Check("alpha_in_attached_band", _finite(al) and alo <= float(al) <= ahi, al, f"{alo}-{ahi}"))
    re = a.get("Re_mac")
    rlo, rhi = RE_RANGE
    res.checks.append(Check("Re_in_range", _finite(re) and rlo <= float(re) <= rhi, re, f"{rlo}-{rhi}"))
    if parent_fidelity is not None:
        res.checks.append(
            Check("fidelity_matches_parent", a.get("fidelity") == parent_fidelity,
                  a.get("fidelity"), parent_fidelity)
        )
    return res
