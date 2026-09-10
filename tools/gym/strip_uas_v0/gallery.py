"""Write parent→child gallery artifacts."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from .aero_l1 import estimate_aero
from .search import run_search
from .wing import WingState


def default_parents(n: int = 5, seed: int = 0) -> list[WingState]:
    import numpy as np

    rng = np.random.default_rng(seed)
    base = WingState()
    parents = [base]
    for _ in range(n - 1):
        parents.append(
            WingState(
                span_m=float(rng.uniform(1.2, 4.0)),
                chord_root_m=float(rng.uniform(0.15, 0.45)),
                taper=float(rng.uniform(0.5, 0.95)),
                sweep_deg=float(rng.uniform(0.0, 15.0)),
                tc=float(rng.uniform(0.10, 0.15)),
                twist_deg=float(rng.uniform(-4.0, 0.0)),
                alpha_deg=float(rng.uniform(0.0, 4.0)),
            )
        )
    return parents


def write_gallery(
    out_dir: Path,
    n_parents: int = 5,
    steps: int = 40,
    seed: int = 0,
    prefer_neuralfoil: bool = True,
) -> dict[str, Any]:
    out_dir = Path(out_dir)
    children_dir = out_dir / "children"
    evidence_dir = out_dir / "evidence"
    children_dir.mkdir(parents=True, exist_ok=True)
    parents = default_parents(n_parents, seed=seed)
    parent_meta = []
    for i, p in enumerate(parents):
        a = estimate_aero(p, prefer_neuralfoil=prefer_neuralfoil)
        parent_meta.append(
            {
                "index": i,
                "ld": a.LD,
                "cd": a.CD,
                "fidelity": a.fidelity,
                "wing": p.to_dict(),
            }
        )
    results = run_search(
        parents,
        steps=steps,
        seed=seed,
        evidence_root=evidence_dir,
        prefer_neuralfoil=prefer_neuralfoil,
    )
    improved = [r for r in results if r.get("improved")]
    for j, r in enumerate(results):
        (children_dir / f"child_{j:03d}.json").write_text(
            json.dumps(r, indent=2, sort_keys=True)
        )
    deltas = [r.get("delta_ld_vs_parent") or -1e9 for r in results if "delta_ld_vs_parent" in r]
    manifest = {
        "n_parents": n_parents,
        "steps": steps,
        "seed": seed,
        "n_results": len(results),
        "n_improved": len(improved),
        "parents": parent_meta,
        "best_delta_ld": max(deltas) if deltas else 0.0,
        "prefer_neuralfoil": prefer_neuralfoil,
    }
    (out_dir / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True))
    lines = [
        "# Strip-UAS-v0 gallery",
        "",
        f"- Parents: {n_parents}",
        f"- Results: {len(results)}",
        f"- Improved L/D vs parent: {len(improved)}",
        f"- Best ΔL/D: {manifest['best_delta_ld']:.6f}",
        "",
        "Fidelity: L0 geometric monitors + L1 NeuralFoil/analytic aero.",
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
            f"ΔLD={r.get('delta_ld_vs_parent'):.6f} LD={r.get('ld'):.6f}"
        )
    (out_dir / "summary.md").write_text("\n".join(lines) + "\n")
    return manifest
