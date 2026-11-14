"""Multi-point mission reward for Strip-UAS-v0 (``mission_multipoint_v0``).

A single-alpha L/D reward lets search tune a wing for one flight condition. Here
each candidate is flown (quasi-statically) at several mission points with the
same mass: at each point the wing is trimmed to the lift coefficient the weight
needs at that speed, ``CL_req = m·g / (½ρV²S)``, by solving the L1 aero oracle
for alpha, and a point-specific figure of merit is scored:

* ``range``     — L/D at the cruise point (higher is better; Breguet-style proxy)
* ``endurance`` — CL^1.5/CD at the loiter point (higher is better; propeller
                  endurance proxy)
* ``climb``     — power required D·V at the climb speed in level flight
                  (lower is better; with fixed power available, lower P_req means
                  more excess power for climb — a proxy, no propulsion model)

Per point ``d`` is the relative improvement over the parent (positive = better);
``score = weighted_mean(d) + worst_case_weight·min(0, min d)``. A point is
credited only when both wings trim inside the oracle's attached-flow band and
pass the aero acceptance gate at the same fidelity.

Honest limits: wing-alone aero (no fuselage / tail / propeller drag), sea-level
ISA, quasi-steady points, mass and speeds are user conventions, and the L1
oracle's wing CL uses a section lift slope with a sweep knock-down (no
finite-span lift-slope correction), so trim alphas are optimistic. Not a
mission-performance prediction; not FAA / ARP6983.
"""

from __future__ import annotations

import dataclasses
from dataclasses import dataclass, field
from typing import Any, Sequence

from .acceptance import accept_aero
from .aero_l1 import G, RHO_SL, estimate_aero
from .wing import ALPHA_MAX, ALPHA_MIN, WingState

LABEL = "mission_multipoint_v0"
METRICS = ("range", "endurance", "climb")


@dataclass(frozen=True)
class MissionPoint:
    name: str
    V_mps: float
    metric: str
    weight: float = 1.0

    def __post_init__(self) -> None:
        if self.metric not in METRICS:
            raise ValueError(f"metric must be one of {METRICS}")


@dataclass(frozen=True)
class Mission:
    mass_kg: float = 5.0  # convention for a small fixed-wing UAS
    points: tuple[MissionPoint, ...] = (
        MissionPoint("cruise", 22.0, "range"),
        MissionPoint("climb", 16.0, "climb"),
        MissionPoint("loiter", 13.0, "endurance"),
    )
    worst_case_weight: float = 1.0

    def to_dict(self) -> dict[str, Any]:
        return {"label": LABEL, "mass_kg": self.mass_kg,
                "points": [dataclasses.asdict(p) for p in self.points],
                "worst_case_weight": self.worst_case_weight}


def _aero(w: WingState, alpha: float, V: float, prefer_neuralfoil: bool):
    return estimate_aero(dataclasses.replace(w, alpha_deg=float(alpha)), u_mps=V,
                         prefer_neuralfoil=prefer_neuralfoil)


def trim(w: WingState, cl_req: float, V: float, *, prefer_neuralfoil: bool = True,
         tol: float = 2e-3, max_iter: int = 6) -> dict[str, Any]:
    """Alpha (within the wing alpha band) where the L1 wing CL equals ``cl_req``."""
    grid = [ALPHA_MIN, 0.0, 4.0, 8.0, ALPHA_MAX]
    vals = [(a, _aero(w, a, V, prefer_neuralfoil)) for a in grid]
    lo = hi = None
    for (a0, r0), (a1, r1) in zip(vals, vals[1:]):
        if (r0.CL - cl_req) * (r1.CL - cl_req) <= 0 and r1.CL != r0.CL:
            lo, hi = (a0, r0), (a1, r1)
            break
    if lo is None:
        return {"trimmed": False, "reason": "CL_req_outside_alpha_band", "CL_req": cl_req,
                "CL_range": [vals[0][1].CL, vals[-1][1].CL]}
    best = lo if abs(lo[1].CL - cl_req) < abs(hi[1].CL - cl_req) else hi
    for _ in range(max_iter):  # regula falsi
        (a0, r0), (a1, r1) = lo, hi
        a = a0 + (cl_req - r0.CL) * (a1 - a0) / (r1.CL - r0.CL)
        r = _aero(w, a, V, prefer_neuralfoil)
        best = (a, r)
        if abs(r.CL - cl_req) <= tol:
            break
        if (r0.CL - cl_req) * (r.CL - cl_req) <= 0:
            hi = (a, r)
        else:
            lo = (a, r)
    a, r = best
    return {"trimmed": abs(r.CL - cl_req) <= 5 * tol, "alpha_deg": float(a), "aero": r,
            "CL_req": cl_req, "CL_err": float(r.CL - cl_req)}


def evaluate_point(w: WingState, p: MissionPoint, mass_kg: float, *,
                   prefer_neuralfoil: bool = True) -> dict[str, Any]:
    q = 0.5 * RHO_SL * p.V_mps**2
    S = w.area_m2()
    cl_req = mass_kg * G / (q * S)
    t = trim(w, cl_req, p.V_mps, prefer_neuralfoil=prefer_neuralfoil)
    row: dict[str, Any] = {"name": p.name, "V_mps": p.V_mps, "metric": p.metric, "CL_req": cl_req}
    if not t["trimmed"]:
        return {**row, "trimmed": False, "reason": t.get("reason", "trim_not_converged"),
                "accepted": False, "value": None}
    a = t["aero"]
    acc = accept_aero(a).to_dict()
    drag = q * S * a.CD
    if p.metric == "range":
        value = a.CL / a.CD
    elif p.metric == "endurance":
        value = max(a.CL, 0.0) ** 1.5 / a.CD
    else:
        value = drag * p.V_mps  # W, lower is better
    return {**row, "trimmed": True, "alpha_deg": t["alpha_deg"], "CL": a.CL, "CD": a.CD,
            "drag_N": drag, "value": float(value), "fidelity": a.fidelity,
            "acceptance": acc, "accepted": bool(acc["passed"])}


def evaluate_mission(w: WingState, mission: Mission = Mission(), *,
                     prefer_neuralfoil: bool = True) -> list[dict[str, Any]]:
    return [evaluate_point(w, p, mission.mass_kg, prefer_neuralfoil=prefer_neuralfoil)
            for p in mission.points]


def mission_score(child: WingState, parent: WingState, mission: Mission = Mission(), *,
                  prefer_neuralfoil: bool = True,
                  parent_eval: Sequence[dict[str, Any]] | None = None) -> dict[str, Any]:
    pe = list(parent_eval) if parent_eval is not None else evaluate_mission(
        parent, mission, prefer_neuralfoil=prefer_neuralfoil)
    ce = evaluate_mission(child, mission, prefer_neuralfoil=prefer_neuralfoil)
    rows = []
    for p, c, pr in zip(mission.points, ce, pe):
        ok = (c["accepted"] and pr["accepted"] and c.get("fidelity") == pr.get("fidelity")
              and pr["value"] not in (None, 0.0))
        d = None
        if ok:
            if p.metric == "climb":
                d = (pr["value"] - c["value"]) / pr["value"]
            else:
                d = (c["value"] - pr["value"]) / abs(pr["value"])
        rows.append({"name": p.name, "metric": p.metric, "weight": p.weight, "credited": ok,
                     "d": d, "child": c, "parent": pr})
    cred = [r for r in rows if r["credited"]]
    out: dict[str, Any] = {"label": LABEL, "mission": mission.to_dict(), "points": rows,
                           "n_credited": len(cred), "accepted": len(cred) == len(rows),
                           "notes": "Wing-alone quasi-steady mission proxy; not a performance prediction."}
    if not cred:
        return {**out, "score": None, "reason": "no_point_credited"}
    wsum = sum(r["weight"] for r in cred) or 1.0
    mean_d = sum(r["weight"] * r["d"] for r in cred) / wsum
    worst = min(cred, key=lambda r: r["d"])
    return {**out, "score": mean_d + mission.worst_case_weight * min(0.0, worst["d"]),
            "mean_d": mean_d, "worst_d": worst["d"], "worst_point": worst["name"]}


def summarize(ms: dict[str, Any]) -> dict[str, Any]:
    """Compact form for evidence / info (drops AeroResult objects)."""
    def slim(r: dict[str, Any]) -> dict[str, Any]:
        return {k: v for k, v in r.items() if k not in ("acceptance",)}
    return {k: v for k, v in ms.items() if k != "points"} | {
        "points": [{"name": r["name"], "d": r["d"], "credited": r["credited"],
                    "child": slim(r["child"]), "parent": slim(r["parent"])} for r in ms["points"]]}
