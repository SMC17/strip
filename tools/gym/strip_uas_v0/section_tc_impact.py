"""Reward impact of modelling w.tc in the NeuralFoil section (honest before/after).

Before: every design was evaluated on the NACA 0012 section, whatever its w.tc.
After: a symmetric NACA 00xx at the design t/c (aero_l1.MAP_SECTION_TC). This module
re-runs both on the same designs and reports how CD, L/D, rankings and the env reward move.
Exploratory L1; not FAA / ARP6983.
"""

from __future__ import annotations

import contextlib
import dataclasses
import json
from pathlib import Path
from typing import Any

import numpy as np

from . import aero_l1
from .env import _reward
from .structure import spar_check
from .wing import WingState

SCHEMA = "strip_uas_v0.section_tc_impact.v1"


@contextlib.contextmanager
def _mapping(on: bool):
    old = aero_l1.MAP_SECTION_TC
    aero_l1.MAP_SECTION_TC = on
    try:
        yield
    finally:
        aero_l1.MAP_SECTION_TC = old


def _both(w: WingState) -> tuple[Any, Any]:
    with _mapping(False):
        a0 = aero_l1.estimate_aero(w)
    with _mapping(True):
        a1 = aero_l1.estimate_aero(w)
    return a0, a1


def _rank(x: np.ndarray) -> np.ndarray:
    return np.argsort(np.argsort(x))


def _spearman(a: np.ndarray, b: np.ndarray) -> float:
    return float(np.corrcoef(_rank(a), _rank(b))[0, 1])


def _random_designs(n: int, seed: int) -> list[WingState]:
    rng = np.random.default_rng(seed)
    out = []
    for _ in range(n):
        out.append(WingState(span_m=rng.uniform(1.6, 3.4), chord_root_m=rng.uniform(0.2, 0.42),
                             taper=rng.uniform(0.4, 1.0), sweep_deg=rng.uniform(0, 20), tc=rng.uniform(0.08, 0.18),
                             twist_deg=rng.uniform(-4, 0), alpha_deg=rng.uniform(0, 6)))
    return out


def analyse(n_designs: int = 300, seed: int = 0) -> dict[str, Any]:
    parent = WingState()
    p0, p1 = _both(parent)
    sweep = []
    for tc in np.round(np.arange(0.08, 0.1801, 0.01), 3):
        w = dataclasses.replace(parent, tc=float(tc))
        a0, a1 = _both(w)
        r0 = _reward(w, p0.LD, parent.area_m2(), parent_cd=p0.CD, aero=a0)
        r1 = _reward(w, p1.LD, parent.area_m2(), parent_cd=p1.CD, aero=a1)
        sweep.append({"tc": float(tc), "CD_before": a0.CD, "CD_after": a1.CD, "LD_before": a0.LD,
                      "LD_after": a1.LD, "CL_before": a0.CL, "CL_after": a1.CL,
                      "reward_before": r0, "reward_after": r1})
    camber_sweep = []
    for m in (0.0, 0.01, 0.02, 0.03, 0.04, 0.05, 0.06):
        w = dataclasses.replace(parent, camber=m)
        with _mapping(True):
            a = aero_l1.estimate_aero(w)
        camber_sweep.append({"camber": m, "CL": a.CL, "CD": a.CD, "LD": a.LD,
                             "reward": _reward(w, p1.LD, parent.area_m2(), parent_cd=p1.CD, aero=a)})
    ds = _random_designs(n_designs, seed)
    ab = [_both(w) for w in ds]
    cd0 = np.array([a.CD for a, _ in ab]); cd1 = np.array([b.CD for _, b in ab])
    ld0 = np.array([a.LD for a, _ in ab]); ld1 = np.array([b.LD for _, b in ab])
    tcs = np.array([w.tc for w in ds])
    k = max(1, n_designs // 10)
    top0, top1 = set(np.argsort(-ld0)[:k]), set(np.argsort(-ld1)[:k])
    # Structural floor (structure.spar_check): ranking among feasible designs, and the
    # L/D-optimal t/c per planform with and without the floor.
    feas = np.array([spar_check(w).feasible for w in ds])
    ld1f = np.where(feas, ld1, -np.inf)
    top1f = set(np.argsort(-ld1f)[:k])
    grid = np.round(np.arange(0.08, 0.1801, 0.01), 3)
    opt_free, opt_floor, binds = [], [], 0
    for w in ds[: min(100, n_designs)]:
        with _mapping(True):
            lds = [aero_l1.estimate_aero(dataclasses.replace(w, tc=float(t))).LD for t in grid]
        req = spar_check(w).tc_required
        opt_free.append(float(grid[int(np.argmax(lds))]))
        ok = [i for i, t in enumerate(grid) if t >= req]
        if ok:
            i = max(ok, key=lambda i: lds[i])
            opt_floor.append(float(grid[i]))
            binds += int(i == ok[0] and ok[0] > 0)
    opt_free_a, opt_floor_a = np.asarray(opt_free), np.asarray(opt_floor)
    structural = {
        "basis": "structure.spar_check (14 CFR 23.337/23.303 loads by convention, elliptic loading, Wood Handbook spruce caps, cap-geometry conventions, 5 kg)",
        "share_random_designs_infeasible": float(1 - feas.mean()),
        "mean_tc_top_decile_after_feasible_only": float(tcs[list(top1f)].mean()),
        "n_planforms": len(opt_free),
        "optimal_tc_free": {"median": float(np.median(opt_free_a)), "share_at_lower_bound": float(np.mean(opt_free_a <= 0.08 + 1e-9))},
        "optimal_tc_with_floor": {"n_with_feasible_tc": len(opt_floor), "median": float(np.median(opt_floor_a)) if opt_floor else None,
                                  "share_at_lower_bound": float(np.mean(opt_floor_a <= 0.08 + 1e-9)) if opt_floor else None,
                                  "share_floor_binding": binds / max(len(opt_floor), 1),
                                  "share_planforms_with_no_feasible_tc": 1 - len(opt_floor) / len(opt_free)},
    }
    return {
        "schema": SCHEMA,
        "structural_floor": structural,
        "parent": parent.to_dict() if hasattr(parent, "to_dict") else dataclasses.asdict(parent),
        "parent_before": {"CD": p0.CD, "LD": p0.LD}, "parent_after": {"CD": p1.CD, "LD": p1.LD},
        "tc_sweep_on_parent": sweep,
        "camber_sweep_on_parent": camber_sweep,
        "random_designs": {
            "n": n_designs, "seed": seed,
            "spearman_LD_before_vs_after": _spearman(ld0, ld1),
            "spearman_CD_before_vs_after": _spearman(cd0, cd1),
            "top_decile_LD_overlap": len(top0 & top1) / k,
            "median_rel_CD_change_pct": float(np.median((cd1 - cd0) / cd0 * 100)),
            "spearman_tc_vs_LD_before": _spearman(tcs, ld0),
            "spearman_tc_vs_LD_after": _spearman(tcs, ld1),
            "mean_tc_top_decile_before": float(tcs[list(top0)].mean()),
            "mean_tc_top_decile_after": float(tcs[list(top1)].mean()),
        },
    }


def render_markdown(r: dict[str, Any]) -> str:
    rd = r["random_designs"]
    L = ["# Reward impact of modelling wing thickness (w.tc) in the gym section", "",
         f"Schema `{r['schema']}`. Before: NACA 0012 for every design. After: symmetric NACA 00xx at w.tc "
         "(exact Kulfan scaling). NeuralFoil small, free transition, U = 25 m/s, sea level.", "",
         "## t/c sweep on the default parent (only tc changed)", "",
         "| t/c | CL before | CL after | CD before | CD after | L/D before | L/D after | reward before | reward after |", "|---|---|---|---|---|---|---|---|---|"]
    for s in r["tc_sweep_on_parent"]:
        L.append(f"| {s['tc']:.2f} | {s['CL_before']:.4f} | {s['CL_after']:.4f} | {s['CD_before']:.5f} | {s['CD_after']:.5f} | {s['LD_before']:.2f} | "
                 f"{s['LD_after']:.2f} | {s['reward_before']:+.3f} | {s['reward_after']:+.3f} |")
    L += ["", f"## {rd['n']} random designs (seed {rd['seed']})", "",
          f"- Spearman L/D before vs after: {rd['spearman_LD_before_vs_after']:.3f}; CD: {rd['spearman_CD_before_vs_after']:.3f}",
          f"- Top-decile L/D overlap: {rd['top_decile_LD_overlap']:.0%}",
          f"- Median CD change: {rd['median_rel_CD_change_pct']:+.1f}%",
          f"- Spearman(t/c, L/D): before {rd['spearman_tc_vs_LD_before']:+.2f}, after {rd['spearman_tc_vs_LD_after']:+.2f}",
          f"- Mean t/c of top-decile designs: before {rd['mean_tc_top_decile_before']:.3f}, after {rd['mean_tc_top_decile_after']:.3f}",
          ""]
    if r.get("camber_sweep_on_parent"):
        L += ["## Camber sweep on the default parent (NACA 4-digit, camber at 0.4 c; t/c 0.12)", "",
              "| camber | CL | CD | L/D | reward |", "|---|---|---|---|---|"]
        for c in r["camber_sweep_on_parent"]:
            L.append(f"| {c['camber']:.2f} | {c['CL']:.3f} | {c['CD']:.5f} | {c['LD']:.1f} | {c['reward']:+.3f} |")
        L += ["", "Camber is a strong reward lever at fixed alpha (it adds lift at the same angle); the trimmed mission "
              "reward is the fair comparison. Measured sections back the section model to ~6% camber "
              "(neuralfoil_polar_validation.md, `gym_section`).", ""]
    sf = r.get("structural_floor")
    if sf:
        of, ol = sf["optimal_tc_free"], sf["optimal_tc_with_floor"]
        L += ["## With the spar-depth floor", "", f"Basis: {sf['basis']}.", "",
              f"- Random designs violating the floor: {sf['share_random_designs_infeasible']:.0%}; mean t/c of the top decile "
              f"among feasible designs: {sf['mean_tc_top_decile_after_feasible_only']:.3f}.",
              f"- L/D-optimal t/c per planform ({sf['n_planforms']} planforms, t/c grid 0.08-0.18): without the floor median "
              f"{of['median']:.2f}, {of['share_at_lower_bound']:.0%} at the 0.08 bound; with the floor median "
              f"{ol['median']:.2f}, {ol['share_at_lower_bound']:.0%} at 0.08, floor binding in {ol['share_floor_binding']:.0%}, "
              f"no feasible t/c in {ol['share_planforms_with_no_feasible_tc']:.0%}.", ""]
    L += ["## Reading this honestly", "",
          "- Before, thickness was free in the reward (reward did not move with t/c), so the search could drift to any t/c "
          "at no cost. After, the reward has a thickness gradient from NeuralFoil.",
          "- The section-only reward favours thin sections. The spar-depth floor (L0 violation "
          "`tc_below_spar_depth_floor`) now ties the minimum t/c to span, root chord and mass, so high-AR / small-chord "
          "planforms are pushed to their floor instead of 0.08; low-AR, large-chord planforms still go to 0.08 because "
          "a spruce-capped 5 kg wing genuinely does not need more depth there. Volume (fuel/battery) is not constrained.",
          "- The L/D used here is at fixed alpha; the mission reward (trimmed C_L) is the better thickness trade.",
          "- Most of the L/D change at fixed alpha comes from C_L, not C_D: at Re ~4e5 and alpha_eff ~1 deg NeuralFoil gives "
          "thin sections a higher lift slope (laminar-separation effects on thick sections). The reward's 2x L/D term "
          "amplifies this; an L/D gain at fixed alpha is not the same as lower drag at fixed lift.",
          "- Section is symmetric (no camber), and at low Re NeuralFoil's thin-section advantage includes laminar-bubble "
          "effects that the measured symmetric sections only partly confirm (see neuralfoil_polar_validation.md, `gym_section`).",
          "- Not FAA / ARP6983; exploratory L1."]
    return "\n".join(L) + "\n"


def write_reports(out_dir: str | Path) -> dict[str, Any]:
    out = Path(out_dir); out.mkdir(parents=True, exist_ok=True)
    r = analyse()
    (out / "section_tc_impact.json").write_text(json.dumps(r, indent=2, sort_keys=True) + "\n")
    (out / "section_tc_impact.md").write_text(render_markdown(r))
    return r


if __name__ == "__main__":
    import sys
    write_reports(sys.argv[1] if len(sys.argv) > 1 else "reports/validation")
