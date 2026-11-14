"""Write parent→child gallery artifacts."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from .aero_l1 import estimate_aero
from .search import run_search
from .wing import WingState


MIN_PARENT_CL = 0.05
MAX_PARENT_TRIES = 50


def screen_parent(w: WingState, *, prefer_neuralfoil: bool = True) -> dict[str, Any]:
    """Is ``w`` a usable starting wing? L0-feasible, accepted cheap aero, CL > 0.05, L/D > 0.

    A parent with negative lift makes "improvement" meaningless: a child that merely
    flips the sign of CL shows a huge Delta L/D (e.g. -16 -> +25 read as +41).
    Screening uses the cheap fidelity (never VSPAERO) so it is fast and fixed.
    """
    from .acceptance import accept_aero
    from .wing import evaluate_l0

    l0 = evaluate_l0(w)
    a = estimate_aero(w, prefer_neuralfoil=prefer_neuralfoil, prefer_vspaero=False)
    acc = accept_aero(a, wing=w)
    reasons = []
    if not l0.feasible:
        reasons.append("l0_infeasible")
    if not acc.passed:
        reasons.append("acceptance_failed:" + ",".join(acc.failed_checks))
    if not (a.CL > MIN_PARENT_CL):
        reasons.append(f"CL<={MIN_PARENT_CL}")
    if not (a.LD > 0):
        reasons.append("LD<=0")
    return {"ok": not reasons, "reasons": reasons, "CL": a.CL, "LD": a.LD, "fidelity": a.fidelity}


def default_parents(
    n: int = 5,
    seed: int = 0,
    *,
    prefer_neuralfoil: bool = True,
    max_tries: int = MAX_PARENT_TRIES,
    stats: dict[str, Any] | None = None,
) -> list[WingState]:
    """Base wing + random wings, each screened by ``screen_parent``.

    Each random slot is resampled up to ``max_tries`` times; raises if a slot
    cannot be filled (no silent fallback to an unscreened wing).
    """
    import numpy as np

    rng = np.random.default_rng(seed)
    base = WingState()
    chk = screen_parent(base, prefer_neuralfoil=prefer_neuralfoil)
    if not chk["ok"]:
        raise ValueError(f"base wing fails parent screen: {chk['reasons']}")
    parents = [base]
    rejected: list[dict[str, Any]] = []
    for slot in range(n - 1):
        for _ in range(int(max_tries)):
            w = WingState(
                span_m=float(rng.uniform(1.2, 4.0)),
                chord_root_m=float(rng.uniform(0.15, 0.45)),
                taper=float(rng.uniform(0.5, 0.95)),
                sweep_deg=float(rng.uniform(0.0, 15.0)),
                tc=float(rng.uniform(0.10, 0.15)),
                twist_deg=float(rng.uniform(-4.0, 0.0)),
                alpha_deg=float(rng.uniform(0.0, 4.0)),
            )
            chk = screen_parent(w, prefer_neuralfoil=prefer_neuralfoil)
            if chk["ok"]:
                parents.append(w)
                break
            rejected.append({"slot": slot + 1, "reasons": chk["reasons"], "CL": chk["CL"], "LD": chk["LD"]})
        else:
            raise ValueError(f"could not draw a screened parent for slot {slot + 1} in {max_tries} tries")
    if stats is not None:
        stats.update({"n_rejected": len(rejected), "rejected": rejected[:20],
                      "min_cl": MIN_PARENT_CL, "max_tries": int(max_tries)})
    return parents


def write_gallery(
    out_dir: Path,
    n_parents: int = 5,
    steps: int = 40,
    seed: int = 0,
    prefer_neuralfoil: bool = True,
    prefer_vspaero: bool = False,
) -> dict[str, Any]:
    out_dir = Path(out_dir)
    children_dir = out_dir / "children"
    evidence_dir = out_dir / "evidence"
    children_dir.mkdir(parents=True, exist_ok=True)
    parent_screen: dict[str, Any] = {}
    parents = default_parents(n_parents, seed=seed, prefer_neuralfoil=prefer_neuralfoil, stats=parent_screen)
    parent_meta = []
    for i, p in enumerate(parents):
        a = estimate_aero(
            p, prefer_neuralfoil=prefer_neuralfoil, prefer_vspaero=prefer_vspaero
        )
        parent_meta.append(
            {
                "index": i,
                "ld": a.LD,
                "cd": a.CD,
                "fidelity": a.fidelity,
                "vspaero_used": a.vspaero_used,
                "wing": p.to_dict(),
            }
        )
    results = run_search(
        parents,
        steps=steps,
        seed=seed,
        evidence_root=evidence_dir,
        prefer_neuralfoil=prefer_neuralfoil,
        prefer_vspaero=prefer_vspaero,
    )
    improved = [r for r in results if r.get("improved")]
    for j, r in enumerate(results):
        (children_dir / f"child_{j:03d}.json").write_text(
            json.dumps(r, indent=2, sort_keys=True)
        )
    deltas = [r.get("delta_ld_vs_parent") or -1e9 for r in results if "delta_ld_vs_parent" in r]
    manifest = {
        "n_parents": n_parents,
        "parent_screen": parent_screen,
        "steps": steps,
        "seed": seed,
        "n_results": len(results),
        "n_improved": len(improved),
        "parents": parent_meta,
        "best_delta_ld": max(deltas) if deltas else 0.0,
        "prefer_neuralfoil": prefer_neuralfoil,
        "prefer_vspaero": prefer_vspaero,
    }
    (out_dir / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True))
    lines = [
        "# Strip-UAS-v0 gallery",
        "",
        f"- Parents: {n_parents}",
        f"- Results: {len(results)}",
        f"- Improved L/D vs parent: {len(improved)}",
        f"- Best ΔL/D: {manifest['best_delta_ld']:.6f}",
        f"- prefer_vspaero: {prefer_vspaero}",
        "",
        "Fidelity: L0 geometric monitors + L1 NeuralFoil/analytic "
        "(optional VSPAERO VLM reward).",
        "Not FAA cert / not ARP6983 / not operational.",
        "",
    ]
    for r in sorted(
        [x for x in results if "ld" in x],
        key=lambda z: z.get("delta_ld_vs_parent") or -1e9,
        reverse=True,
    )[:10]:
        lines.append(
            f"- {r.get('method')} parent={r.get('parent_index')} "
            f"ΔLD={r.get('delta_ld_vs_parent'):.6f} LD={r.get('ld'):.6f} "
            f"fid={r.get('fidelity')}"
        )
    (out_dir / "summary.md").write_text("\n".join(lines) + "\n")
    return manifest
