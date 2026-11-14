"""Strip applications of ``conformal.py`` (labelled; read-only consumers of data/ and other modules).

1. ``section_vs_tunnel`` — NeuralFoil NACA 0012 section cd and cl vs Ladson,
   NASA TM-4074 (Re 6e6, M 0.15, transition tripped; vendored in
   ``data/vendored/``) over the attached range |alpha| ≤ ``alpha_max``. A real
   measurement, but one airfoil, one Re, three grit sizes: the grit zones are
   used as groups for leave-one-group-out coverage. NeuralFoil is run with
   ``xtr = 0.05`` on both surfaces as a stated stand-in for the trip (the grit
   location is not modelled exactly) and Mach is ignored.
2. ``l1_vs_vlm`` — the gym's L1 wing CL vs the in-repo planar VLM CL at the
   same alpha on wings drawn i.i.d. from a stated sampler (exchangeable). The L1
   oracle has no finite-span lift-slope correction, so this calibrates a known,
   structured model gap; model-vs-model, not truth.
"""

from __future__ import annotations

import dataclasses
from pathlib import Path
from typing import Any

import numpy as np

from .conformal import SplitConformal, group_cv, random_split_coverage
from .wing import WingState, evaluate_l0

LADSON = Path(__file__).resolve().parents[3] / "data" / "vendored" / "ladson_naca0012_tm4074_re6e6_tripped.dat"
SAMPLER = {"span_m": (1.2, 4.0), "chord_root_m": (0.15, 0.45), "taper": (0.4, 1.0),
           "sweep_deg": (0.0, 25.0), "twist_deg": (-4.0, 0.0), "alpha_deg": (0.0, 8.0)}


def load_ladson(path: Path = LADSON) -> list[dict[str, Any]]:
    rows, zone = [], None
    for line in path.read_text().splitlines():
        s = line.strip()
        if not s or s.startswith("#") or s.startswith("variables"):
            continue
        if s.lower().startswith("zone"):
            zone = s.split('"')[1] if '"' in s else s
            continue
        a, cl, cd = (float(x) for x in s.split()[:3])
        rows.append({"zone": zone, "alpha_deg": a, "cl": cl, "cd": cd})
    return rows


def section_vs_tunnel(*, alpha: float = 0.1, alpha_max: float = 12.0, xtr: float = 0.05) -> dict[str, Any]:
    import neuralfoil as nf

    from .teachers.neuralfoil_stub import _default_kulfan

    rows = [r for r in load_ladson() if abs(r["alpha_deg"]) <= alpha_max]
    a = np.array([r["alpha_deg"] for r in rows])
    out = nf.get_aero_from_kulfan_parameters(_default_kulfan(), alpha=a, Re=6e6, xtr_upper=xtr,
                                             xtr_lower=xtr, model_size="xlarge")
    zones = [r["zone"] for r in rows]
    res: dict[str, Any] = {"type": "conformal_calibration_set", "source": "Ladson NASA TM-4074 (vendored)",
                           "n_points": len(rows), "alpha_max": alpha_max, "xtr_convention": xtr}
    for q in ("cd", "cl"):
        pred = np.asarray(out["CD" if q == "cd" else "CL"], dtype=float)
        ref = np.array([r[q] for r in rows])
        # cl crosses zero near alpha 0, so its score is absolute; cd is relative
        score = "rel" if q == "cd" else "abs"
        cp = SplitConformal(alpha, score).fit(pred, ref)
        res[q] = cp.to_evidence(
            surrogate=f"NeuralFoil NACA0012 section {q} (xtr={xtr})", reference=f"Ladson tunnel {q}",
            extra={"leave_one_grit_out": group_cv(pred, ref, zones, alpha=alpha, score=score),
                   "median_signed_err": float(np.median(pred - ref))})
    return res


def sample_wings(n: int, seed: int = 0) -> list[WingState]:
    rng = np.random.default_rng(seed)
    out: list[WingState] = []
    while len(out) < n:
        w = WingState(**{k: float(rng.uniform(*v)) for k, v in SAMPLER.items()})
        if evaluate_l0(w).feasible:
            out.append(w)
    return out


def l1_vs_vlm(n: int = 120, *, alpha: float = 0.1, seed: int = 0,
              prefer_neuralfoil: bool = False) -> dict[str, Any]:
    from .aero_l1 import estimate_aero
    from .vlm import solve

    wings = sample_wings(n, seed)
    l1 = np.array([estimate_aero(w, prefer_neuralfoil=prefer_neuralfoil).CL for w in wings])
    vlm = np.array([solve(w, n_span=12, n_chord=3)["CL"] for w in wings])
    half = len(wings) // 2
    cp = SplitConformal(alpha, "abs").fit(l1[:half], vlm[:half])
    return cp.to_evidence(
        surrogate=f"L1 wing CL ({'neuralfoil' if prefer_neuralfoil else 'analytic'})",
        reference="planar VLM CL (vlm_planar_v0)", test=cp.evaluate(l1[half:], vlm[half:]),
        extra={"sampler": SAMPLER, "seed": seed, "n_pairs": len(wings),
               "median_l1_minus_vlm": float(np.median(l1 - vlm)),
               "random_splits": random_split_coverage(l1, vlm, alpha=alpha, score="abs"),
               "scope": "model-vs-model; L1 lacks finite-span lift-slope correction"})


def main(argv: list[str] | None = None) -> int:
    import argparse
    import json

    ap = argparse.ArgumentParser(prog="strip_uas_v0.conformal_strip")
    ap.add_argument("--n", type=int, default=120)
    a = ap.parse_args(argv)
    sec = section_vs_tunnel()
    lv = l1_vs_vlm(a.n)
    print(json.dumps({
        "section_cd": {k: sec["cd"][k] for k in ("q_hat", "n_cal", "median_signed_err")}
        | {"logo": sec["cd"]["leave_one_grit_out"]["pooled_coverage"]},
        "section_cl": {k: sec["cl"][k] for k in ("q_hat", "n_cal", "median_signed_err")}
        | {"logo": sec["cl"]["leave_one_grit_out"]["pooled_coverage"]},
        "l1_vs_vlm": {k: lv[k] for k in ("q_hat", "n_cal", "test", "median_l1_minus_vlm")}
        | {"random_splits": lv["random_splits"]["mean_coverage"]}}, indent=1, default=str))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
