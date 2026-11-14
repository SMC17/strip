"""Report: the no-NeuralFoil fallback (thin-airfoil C_l, build-up C_d0, Nita & Scholz Oswald e).

* Section: compared with measured polars (Ladson NACA 0012; LSAT symmetric sections) before
  (old ad-hoc C_d0 + k C_l^2, k = 0.04) and after (2 C_f FF, no lift-dependent profile drag).
* Span efficiency: Nita & Scholz (2012) vs Glauert's lifting-line solution (monoplane
  equation, Anderson §5.3) for unswept trapezoidal wings, and vs the old convention.
Exploratory L1; not FAA / ARP6983.
"""

from __future__ import annotations

import json
import math
from pathlib import Path
from typing import Any

import numpy as np

from . import aero_l1, validation as v

SCHEMA = "strip_uas_v0.analytic_fallback.v1"


def _old_section(alpha_deg: float, tc: float) -> tuple[float, float]:
    cl = max(-1.2, min(1.4, 2.0 * math.pi * math.radians(alpha_deg)))
    cd0 = 0.006 + 0.8 * (tc - 0.12) ** 2
    k = 0.04 + 0.5 * abs(tc - 0.12)
    return cl, cd0 + k * cl * cl


def old_oswald(taper: float) -> float:
    return max(0.6, min(0.95, 0.85 - 0.05 * (1.0 - taper)))


def lifting_line_e(ar: float, taper: float, n: int = 40) -> float:
    """Glauert monoplane equation, odd terms, constant section slope 2*pi, no twist, unswept."""
    th = np.linspace(0, math.pi / 2, n + 1)[1:]  # half span by symmetry
    ks = 2 * np.arange(n) + 1
    b = 1.0
    s = b * b / ar
    cr = 2 * s / (b * (1 + taper))
    y = -b / 2 * np.cos(th)
    c = cr * (1 - (1 - taper) * np.abs(2 * y / b))
    mu = c * 2 * math.pi / (4 * b)
    A = np.sin(np.outer(th, ks)) * (mu[:, None] * ks[None, :] + np.sin(th)[:, None])
    rhs = mu * np.sin(th) * 1.0  # alpha = 1 rad (linear; e independent of alpha)
    a = np.linalg.solve(A, rhs)
    delta = float(np.sum(ks[1:] * (a[1:] / a[0]) ** 2))
    return 1.0 / (1.0 + delta)


def _section_rows(polars) -> dict[str, Any]:
    out = {}
    for name, fn in (("before", lambda a, t, re: _old_section(a, t)),
                     ("after", lambda a, t, re: aero_l1._analytic_section(a, t, re)[:2])):
        ecd, dcl = [], []
        for p in polars:
            t, cam = v.section_geometry(p.coords) if p.coords is not None else (0.12, 0.0)
            if cam > v.SYMMETRIC_CAMBER_TOL:
                continue
            att = p.attached_mask
            for k in np.nonzero(att)[0]:
                cl, cd = fn(float(p.alpha[k]), t, p.Re)
                dcl.append(cl - p.cl[k])
                ecd.append((p.cd[k] - cd) / p.cd[k] * 100)
        ecd, dcl = np.asarray(ecd), np.asarray(dcl)
        out[name] = {"n": int(ecd.size), "median_abs_E_CD_pct": float(np.median(np.abs(ecd))),
                     "mean_E_CD_pct": float(np.mean(ecd)), "median_abs_dCL": float(np.median(np.abs(dcl)))}
    return out


def neuralfoil_path_switch(n: int = 300, seed: int = 0) -> dict[str, Any]:
    """Effect of moving the NeuralFoil path from the old e convention to Nita & Scholz (round 4).

    Same section results; the old wing C_D is rebuilt as C_d,sec + C_L^2/(pi A e_old)."""
    from .section_tc_impact import _random_designs

    ld_new, ld_old, e_new, e_old, nf = [], [], [], [], 0
    for w in _random_designs(n, seed):
        a = aero_l1.estimate_aero(w)
        nf += int(a.neuralfoil_used)
        ar = max(w.aspect_ratio(), 1.0)
        en, eo = aero_l1.span_efficiency(w), old_oswald(w.taper)
        cd_sec = a.CD - a.CL**2 / (math.pi * ar * en)
        cd_old = cd_sec + a.CL**2 / (math.pi * ar * eo)
        ld_new.append(a.LD); ld_old.append(a.CL / max(cd_old, 1e-6)); e_new.append(en); e_old.append(eo)
    ln, lo = np.asarray(ld_new), np.asarray(ld_old)
    rk = lambda x: np.argsort(np.argsort(x))  # noqa: E731
    k = max(1, n // 10)
    return {"n": n, "seed": seed, "n_neuralfoil": nf, "median_e_new": float(np.median(e_new)),
            "median_e_old": float(np.median(e_old)),
            "median_rel_LD_change_pct": float(np.median((ln - lo) / lo * 100)),
            "spearman_LD_old_vs_new": float(np.corrcoef(rk(lo), rk(ln))[0, 1]),
            "top_decile_overlap": len(set(np.argsort(-lo)[:k]) & set(np.argsort(-ln)[:k])) / k}


def analyse() -> dict[str, Any]:
    lad = v.load_ladson()
    lsat_sym = [p for p in v.load_lsat()]
    e_rows = []
    for ar in (6.0, 8.0, 12.0, 18.0):
        for lam in (0.35, 0.5, 0.7, 1.0):
            e_rows.append({"AR": ar, "taper": lam, "e_lifting_line": lifting_line_e(ar, lam),
                           "e_nita_scholz": aero_l1.oswald_nita_scholz(ar, lam, 0.0), "e_old_convention": old_oswald(lam)})
    err_ns = [abs(r["e_nita_scholz"] - r["e_lifting_line"]) for r in e_rows]
    err_old = [abs(r["e_old_convention"] - r["e_lifting_line"]) for r in e_rows]
    return {
        "schema": SCHEMA,
        "neuralfoil_path_switch": neuralfoil_path_switch(),
        "section_ladson_naca0012": _section_rows(lad),
        "section_lsat_symmetric": _section_rows(lsat_sym) if lsat_sym else None,
        "oswald": {"rows": e_rows, "max_abs_err_nita_scholz": max(err_ns), "max_abs_err_old": max(err_old),
                   "mean_abs_err_nita_scholz": float(np.mean(err_ns)), "mean_abs_err_old": float(np.mean(err_old))},
    }


def render_markdown(r: dict[str, Any]) -> str:
    L = ["# No-NeuralFoil fallback: section drag and Oswald factor", "",
         f"Schema `{r['schema']}`. Bases: thin-airfoil C_l; C_d0 = 2 C_f FF (Raymer eqs. 12.27, 12.30; fully turbulent, "
         "(x/c)_m = 0.3 convention); wing e from Nita & Scholz (2012). Attached measured points; E_CD% = (meas - pred)/meas.", "",
         "| data | version | n | median abs E_CD% | mean E_CD% | median abs ΔCL |", "|---|---|---|---|---|---|"]
    for key, label in (("section_ladson_naca0012", "Ladson NACA 0012, Re 6e6 tripped"),
                       ("section_lsat_symmetric", "LSAT symmetric sections, Re 4e4-5e5")):
        blk = r.get(key)
        if not blk:
            continue
        for ver in ("before", "after"):
            s = blk[ver]
            L.append(f"| {label} | {ver} | {s['n']} | {s['median_abs_E_CD_pct']:.1f} | {s['mean_E_CD_pct']:+.1f} | {s['median_abs_dCL']:.3f} |")
    o = r["oswald"]
    L += ["", "## Span efficiency vs Glauert lifting line (unswept, no twist)", "",
          f"Mean |Δe|: Nita & Scholz {o['mean_abs_err_nita_scholz']:.3f}, old convention {o['mean_abs_err_old']:.3f}; "
          f"max |Δe|: {o['max_abs_err_nita_scholz']:.3f} vs {o['max_abs_err_old']:.3f}.", "",
          "| AR | taper | e lifting line | e Nita & Scholz | e old |", "|---|---|---|---|---|"]
    for x in o["rows"]:
        L.append(f"| {x['AR']:.0f} | {x['taper']:.2f} | {x['e_lifting_line']:.3f} | {x['e_nita_scholz']:.3f} | {x['e_old_convention']:.3f} |")
    sw = r.get("neuralfoil_path_switch")
    if sw:
        L += ["", f"## NeuralFoil path switched to Nita & Scholz ({sw['n']} random designs, seed {sw['seed']}, "
              f"{sw['n_neuralfoil']} on NeuralFoil)", "",
              f"- Median e: {sw['median_e_old']:.3f} (old convention) -> {sw['median_e_new']:.3f}",
              f"- Median L/D change: {sw['median_rel_LD_change_pct']:+.1f}%; Spearman L/D old vs new "
              f"{sw['spearman_LD_old_vs_new']:.3f}; top-decile overlap {sw['top_decile_overlap']:.0%}"]
    L += ["", "## Limits", "",
          "- Fully turbulent C_f over-predicts drag for laminar low-Re sections (LSAT): the fallback is conservative there.",
          "- No lift-dependent profile drag and no stall model in the fallback section; thin-airfoil C_l ignores thickness and Re.",
          "- The NeuralFoil path now uses the same Nita & Scholz e (round 4); see the switch block above.",
          "- Not FAA / ARP6983; exploratory L1."]
    return "\n".join(L) + "\n"


def write_reports(out_dir: str | Path) -> dict[str, Any]:
    out = Path(out_dir); out.mkdir(parents=True, exist_ok=True)
    r = analyse()
    (out / "analytic_fallback.json").write_text(json.dumps(r, indent=2, sort_keys=True) + "\n")
    (out / "analytic_fallback.md").write_text(render_markdown(r))
    return r


if __name__ == "__main__":
    import sys
    write_reports(sys.argv[1] if len(sys.argv) > 1 else "reports/validation")
