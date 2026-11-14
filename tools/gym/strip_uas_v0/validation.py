"""NeuralFoil / section-oracle validation against measured wind-tunnel polars.

Reference data (public):

* **Ladson NACA 0012**, NASA TM-4074 (1988), Re = 6e6, M = 0.15, transition
  tripped (80/120/180 grit) — vendored at ``data/vendored/`` (US Government work,
  via the NASA Turbulence Modeling Resource).
* **UIUC LSAT** low-speed airfoil tests, volumes 1-6 (Selig et al.), Re ≈ 4e4-5e5,
  ~110 airfoils — GPL; fetched by ``data/fetch/fetch_strip_data.py`` into the
  git-ignored cache, never committed. Only derived statistics are committed.
  Volumes 1-3 carry the measured model coordinates; volumes 4-6 ship none, so their
  clean, flap-neutral polars are matched to *nominal* UIUC ADS coordinates
  (``LSAT_ADS_MAP``); airfoils with no ADS match are skipped and listed.

Oracles:

* ``neuralfoil_small`` — NeuralFoil ``model_size="small"`` on the measured
  airfoil's coordinates (what the gym calls, but with the right geometry).
* ``neuralfoil_xlarge`` — same, largest model.
* ``gym_section`` — exactly what ``aero_l1._neuralfoil_section`` evaluates: a NACA
  4-digit section with the measured airfoil's t/c, max camber and max-camber position p
  (p clipped to the gym band ``wing.CAMBER_POS_MIN..MAX``), NeuralFoil small. Checked on every measured section whose camber is inside the gym's
  band (<= 6% c). The gym's NACA family cannot represent other camber lines (position,
  reflex, aft loading), so this measures the cost of that family choice too.
* ``gym_section_p04`` — baseline: the same with p fixed at 0.4 (the gym before camber
  position was a design parameter).
* ``gym_section_camber_blind`` — baseline: a symmetric NACA 00xx at the measured t/c on
  every measured airfoil (the gym before camber was a design parameter).
* ``analytic`` — the gym's thin-airfoil / parabolic-drag fallback (NACA 0012 only).

Metrics: ΔC_L = C_L,pred − C_L,meas; drag comparison error
E_CD% = (C_D,meas − C_D,pred) / C_D,meas × 100 (positive = under-predicts drag).
"Attached" points are those at or below the measured C_L,max angle of each polar.

Exploratory; not FAA / EASA, not ARP6983 / ED-324 conformance.
"""

from __future__ import annotations

import json
import math
import re
from dataclasses import dataclass, field
from functools import lru_cache
from pathlib import Path
from typing import Any, Iterable, Sequence

import numpy as np

VALIDATION_SCHEMA = "strip_uas_v0.validation.polars.v1"
ORACLES = ("neuralfoil_small", "neuralfoil_xlarge", "gym_section", "gym_section_p04", "gym_section_camber_blind",
           "analytic")
SYMMETRIC_CAMBER_TOL = 0.005

# Envelope criteria (stated conventions, configurable): a Re band is "validated"
# for an oracle when, over attached points, median |ΔCL| <= CL_TOL and median
# |E_CD| <= CD_TOL_PCT.
CL_TOL = 0.05
CD_TOL_PCT = 15.0
RE_BANDS = ((0.0, 1.0e5), (1.0e5, 2.0e5), (2.0e5, 5.5e5), (1.0e6, 2.0e7))


def repo_root() -> Path:
    for p in Path(__file__).resolve().parents:
        if (p / "data" / "vendored").is_dir():
            return p
    raise FileNotFoundError("repo-root data/ not found")


@dataclass
class Polar:
    airfoil: str
    source: str
    Re: float
    alpha: np.ndarray
    cl: np.ndarray
    cd: np.ndarray
    coords: np.ndarray | None = None
    tripped: bool = False
    meta: dict[str, Any] = field(default_factory=dict)

    @property
    def attached_mask(self) -> np.ndarray:
        if self.cl.size == 0:
            return np.zeros(0, bool)
        a_max = self.alpha[int(np.argmax(self.cl))]
        return self.alpha <= a_max + 1e-9


# ------------------------------------------------------------------ loaders
def load_ladson() -> list[Polar]:
    p = repo_root() / "data" / "vendored" / "ladson_naca0012_tm4074_re6e6_tripped.dat"
    polars, cur, name = [], [], None
    for ln in p.read_text().splitlines():
        if ln.startswith("zone"):
            if cur:
                polars.append((name, cur))
            name, cur = ln.split('"')[1], []
        elif ln and ln[0] in "-.0123456789 ":
            t = ln.split()
            if len(t) == 3:
                cur.append([float(x) for x in t])
    if cur:
        polars.append((name, cur))
    out = []
    for name, rows in polars:
        a = np.asarray(rows)
        out.append(Polar("NACA 0012", f"Ladson NASA TM-4074 ({name})", 6.0e6, a[:, 0], a[:, 1], a[:, 2],
                         coords=naca4_coords("0012"), tripped=True, meta={"grit": name, "Mach": 0.15}))
    return out


def naca4_coords(code: str, n: int = 121) -> np.ndarray:
    m, p, t = int(code[0]) / 100, int(code[1]) / 10, int(code[2:]) / 100
    beta = np.linspace(0, math.pi, n)
    x = (1 - np.cos(beta)) / 2
    yt = 5 * t * (0.2969 * np.sqrt(x) - 0.1260 * x - 0.3516 * x**2 + 0.2843 * x**3 - 0.1036 * x**4)
    if m == 0:
        xu, yu, xl, yl = x, yt, x, -yt
    else:
        yc = np.where(x < p, m / p**2 * (2 * p * x - x**2), m / (1 - p) ** 2 * ((1 - 2 * p) + 2 * p * x - x**2))
        dy = np.where(x < p, 2 * m / p**2 * (p - x), 2 * m / (1 - p) ** 2 * (p - x))
        th = np.arctan(dy)
        xu, yu, xl, yl = x - yt * np.sin(th), yc + yt * np.cos(th), x + yt * np.sin(th), yc - yt * np.cos(th)
    return np.vstack([np.column_stack([xu[::-1], yu[::-1]]), np.column_stack([xl[1:], yl[1:]])])


def lsat_dir() -> Path:
    return repo_root() / "data" / "cache" / "uiuc_lsat"


def lsat_available() -> bool:
    return (lsat_dir() / "volume01" / "DRAG01.TXT").is_file()


def _parse_coords(path: Path) -> dict[str, np.ndarray]:
    parts = re.split(r"^:{10,}\s*$", path.read_text(encoding="latin-1"), flags=re.M)
    out: dict[str, np.ndarray] = {}
    for i in range(1, len(parts) - 1, 2):
        fname = parts[i].strip().lower()
        pts = []
        for ln in parts[i + 1].strip().splitlines()[1:]:
            t = ln.split()
            if len(t) >= 2:
                try:
                    pts.append((float(t[0]), float(t[1])))
                except ValueError:
                    pass
        if len(pts) > 20:
            out[fname] = np.asarray(pts)
    return out


_NAME_OVERRIDES = {"naca6409": "n6409", "naca64a010": "n64a", "fx63-137": "fx63", "ch10-48-13": "ch10",
                   "naca2414": "n2414", "naca2415": "n2415", "clark-y": "clarky", "m06-13-128": "m06",
                   "fx74-cl5-140mod": "fx74mod"}


def _coord_for(name: str, coords: dict[str, np.ndarray]) -> tuple[str, np.ndarray] | None:
    m = re.match(r"^(.*?)\s*(?:\(([A-Z])\))?\s*$", name.strip())
    base, letter = (m.group(1), (m.group(2) or "").lower()) if m else (name, "")
    key = re.sub(r"\s+", "", base.lower())
    key = _NAME_OVERRIDES.get(key, key)
    for cand in (f"{key}{letter}.dap", f"{key}.dap", f"{key}.dat", f"{key}sm.dat"):
        if cand in coords:
            return cand, coords[cand]
    return None


def _parse_drag(path: Path, coords: dict[str, np.ndarray], volume: str) -> list[Polar]:
    lines = path.read_text(encoding="latin-1").splitlines()
    out, i, name, comment = [], 0, None, ""
    while i < len(lines):
        ln = lines[i].strip()
        if ln.startswith("Airfoil:"):
            name = ln.split(":", 1)[1].strip()
        elif ln.startswith("Comment:"):
            comment = ln.split(":", 1)[1].strip()
        elif ln.startswith("Average Reynolds") and name:
            re_ = float(lines[i + 1].split()[0])
            n = int(lines[i + 3].split()[0])
            rows = []
            for r in lines[i + 5 : i + 5 + n]:
                t = r.split()
                if len(t) >= 3:
                    rows.append((float(t[0]), float(t[1]), float(t[2])))
            i += 5 + n
            c = _coord_for(name, coords)
            if rows and c is not None and "clean" in comment.lower():
                a = np.asarray(rows)
                out.append(Polar(name, f"UIUC LSAT vol {volume}", re_, a[:, 0], a[:, 1], a[:, 2],
                                 coords=c[1], meta={"coord_file": c[0], "comment": comment}))
            continue
        i += 1
    return out


# LSAT vols 4-6 airfoil label (lower-case, model letter / flap suffix removed) -> UIUC ADS file.
LSAT_ADS_MAP = {
    "e387": "e387", "fx63-137": "fx63137", "sd2030": "sd2030", "ag12": "ag12", "ag16": "ag16", "ag24": "ag24",
    "ag35": "ag35", "cal1215j": "cal1215j", "cal2263m": "cal2263m", "cal4014l": "cal4014l", "ma409": "ma409",
    "s8064": "s8064", "s9000": "s9000", "w1011-20": "w1011", "w1011-30": "w1011", "w1015-20": "w1015",
    "w1015-30": "w1015",
}
_FLAP_SUFFIX = re.compile(r"\s+f[pn]?(-?[\d.]+)$", re.I)


def ads_dir() -> Path:
    return repo_root() / "data" / "cache" / "uiuc_ads"


def parse_ads_coords(path: Path) -> np.ndarray:
    """UIUC ADS .dat (Selig or Lednicer format) -> Selig-ordered (TE upper -> LE -> TE lower)."""
    rows = []
    for ln in path.read_text(encoding="latin-1").splitlines()[1:]:
        t = ln.split()
        if len(t) >= 2:
            try:
                rows.append((float(t[0]), float(t[1])))
            except ValueError:
                pass
    a = np.asarray(rows)
    if a[0, 0] > 1.5:  # Lednicer: counts line, upper LE->TE, lower LE->TE
        nu, nl = int(a[0, 0]), int(a[0, 1])
        up, lo = a[1 : 1 + nu], a[1 + nu : 1 + nu + nl]
        a = np.vstack([up[::-1], lo[1:]])
    return a


def _lsat_v46_key(name: str, comment: str) -> str | None:
    """ADS key for a clean, flap-neutral vols 4-6 polar, else None."""
    c = comment.lower()
    if "clean" not in c or "serration" in c:
        return None
    m = re.search(r"flap\s*=\s*(-?[\d.]+)", c)
    if m and float(m.group(1)) != 0.0:
        return None
    base = re.sub(r"\s*\([A-Z]\)\s*$", "", name.strip())
    fm = _FLAP_SUFFIX.search(base)
    if fm:
        if float(fm.group(1)) != 0.0:
            return None
        base = base[: fm.start()]
    return LSAT_ADS_MAP.get(re.sub(r"\s+", "", base.lower()))


def _parse_v46(path: Path, volume: str, skipped: set[str]) -> list[Polar]:
    lines = path.read_text(encoding="latin-1").splitlines()
    name = next((ln.split(":", 1)[1].strip() for ln in lines if ln.startswith("Airfoil:")), "")
    comment = next((ln.split(":", 1)[1].strip().strip("'") for ln in lines if ln.startswith("Comment:")), "")
    key = _lsat_v46_key(name, comment)
    if key is None or not (ads_dir() / f"{key}.dat").is_file():
        if "clean" in comment.lower() and key is None and not re.search(r"flap|f[pn]", (comment + name).lower()):
            skipped.add(name)
        return []
    coords = parse_ads_coords(ads_dir() / f"{key}.dat")
    out = []
    for i, ln in enumerate(lines):
        if ln.strip().startswith("Average Reynolds"):
            re_ = float(lines[i + 1].split()[0])
            n = int(lines[i + 3].split()[0])
            rows = [tuple(map(float, r.split()[:3])) for r in lines[i + 5 : i + 5 + n] if len(r.split()) >= 3]
            if rows:
                a = np.asarray(rows)
                label = re.sub(r"\s+f[pn]?0$", "", name.strip())
                out.append(Polar(label, f"UIUC LSAT vol {volume}", re_, a[:, 0], a[:, 1], a[:, 2], coords=coords,
                                 meta={"coord_file": f"uiuc_ads/{key}.dat", "coords": "nominal (UIUC ADS)",
                                       "comment": comment}))
    return out


LSAT_V46_SKIPPED: set[str] = set()


@lru_cache(maxsize=1)
def load_lsat() -> tuple[Polar, ...]:
    if not lsat_available():
        return ()
    polars: list[Polar] = []
    for v in ("01", "02", "03"):
        d = lsat_dir() / f"volume{v}"
        cf, df = d / f"COORD{v}.TXT", d / f"DRAG{v}.TXT"
        if cf.is_file() and df.is_file():
            polars += _parse_drag(df, _parse_coords(cf), v)
    for v in ("04", "05", "06"):
        d = lsat_dir() / f"volume{v}"
        if d.is_dir():
            for f in sorted(list(d.glob("*_drg.txt")) + list(d.glob("*_drag.dat"))):
                polars += _parse_v46(f, v, LSAT_V46_SKIPPED)
    return tuple(polars)


# ------------------------------------------------------------------ geometry
def section_geometry(coords: np.ndarray, n: int = 201) -> tuple[float, float]:
    """(max thickness / chord, max |camber| / chord) from Selig-ordered coordinates."""
    c = np.asarray(coords, float)
    ile = int(np.argmin(c[:, 0]))
    x0, x1 = c[:, 0].min(), c[:, 0].max()
    ch = max(x1 - x0, 1e-9)
    up, lo = c[: ile + 1][::-1], c[ile:]
    xs = x0 + ch * (1 - np.cos(np.linspace(0, math.pi, n))) / 2
    yu = np.interp(xs, up[:, 0], up[:, 1])
    yl = np.interp(xs, lo[:, 0], lo[:, 1])
    if np.mean(yu - yl) < 0:  # coordinates ordered lower-first
        yu, yl = yl, yu
    return float(np.max(yu - yl) / ch), float(np.max(np.abs((yu + yl) / 2 - (yu[0] + yl[0]) / 2)) / ch)


def section_camber_position(coords: np.ndarray, n: int = 201) -> float:
    """x/c of the maximum |camber| (same mean line as ``section_geometry``); 0 for a symmetric section."""
    c = np.asarray(coords, float)
    ile = int(np.argmin(c[:, 0]))
    x0, x1 = c[:, 0].min(), c[:, 0].max()
    ch = max(x1 - x0, 1e-9)
    up, lo = c[: ile + 1][::-1], c[ile:]
    xs = x0 + ch * (1 - np.cos(np.linspace(0, math.pi, n))) / 2
    yu = np.interp(xs, up[:, 0], up[:, 1])
    yl = np.interp(xs, lo[:, 0], lo[:, 1])
    if np.mean(yu - yl) < 0:
        yu, yl = yl, yu
    cam = np.abs((yu + yl) / 2 - (yu[0] + yl[0]) / 2)
    if cam.max() <= 1e-9:
        return 0.0
    return float((xs[int(np.argmax(cam))] - x0) / ch)


def _geom(p: "Polar") -> tuple[float, float]:
    if "tc" not in p.meta:
        p.meta["tc"], p.meta["camber"] = section_geometry(p.coords)
    return p.meta["tc"], p.meta["camber"]


def _camber_pos(p: "Polar") -> float:
    if "camber_pos" not in p.meta:
        p.meta["camber_pos"] = section_camber_position(p.coords)
    return p.meta["camber_pos"]


# ------------------------------------------------------------------ oracles
@lru_cache(maxsize=512)
def _kulfan(key: str) -> dict[str, Any]:
    import aerosandbox as asb

    arr = np.asarray(json.loads(key))
    return dict(asb.Airfoil(name="ref", coordinates=arr).to_kulfan_airfoil().kulfan_parameters)


def _kulfan_for(p: Polar) -> dict[str, Any]:
    return _kulfan(json.dumps(np.round(p.coords, 6).tolist()))


def predict(p: Polar, oracle: str) -> dict[str, np.ndarray] | None:
    import neuralfoil as nf

    n = p.alpha.size
    xtr = 0.05 if p.tripped else 1.0
    if oracle in ("neuralfoil_small", "neuralfoil_xlarge"):
        size = oracle.split("_")[1]
        r = nf.get_aero_from_kulfan_parameters(_kulfan_for(p), alpha=p.alpha, Re=np.full(n, p.Re),
                                               xtr_upper=xtr, xtr_lower=xtr, model_size=size)
        return {"cl": np.asarray(r["CL"]), "cd": np.asarray(r["CD"]), "conf": np.asarray(r["analysis_confidence"])}
    if oracle in ("gym_section", "gym_section_p04", "gym_section_camber_blind"):
        tc, camber = _geom(p)
        from .teachers import neuralfoil_stub
        from .wing import CAMBER_MAX, CAMBER_POS, CAMBER_POS_MAX, CAMBER_POS_MIN

        if oracle in ("gym_section", "gym_section_p04"):
            if camber > CAMBER_MAX:
                return None
            pos = CAMBER_POS if oracle == "gym_section_p04" else min(CAMBER_POS_MAX, max(CAMBER_POS_MIN, _camber_pos(p)))
            kp = neuralfoil_stub.naca4_kulfan(tc, camber if camber > SYMMETRIC_CAMBER_TOL else 0.0, pos)
        else:
            kp = neuralfoil_stub.naca00_kulfan(tc)
        # Gym geometry + model size; transition matched to the experiment so the comparison
        # isolates geometry/model error (the gym itself runs free transition).
        r = nf.get_aero_from_kulfan_parameters(kp, alpha=p.alpha, Re=np.full(n, p.Re),
                                               xtr_upper=xtr, xtr_lower=xtr, model_size="small")
        return {"cl": np.asarray(r["CL"]), "cd": np.asarray(r["CD"]), "conf": np.asarray(r["analysis_confidence"])}
    if oracle == "analytic":
        if p.airfoil != "NACA 0012":
            return None
        from .aero_l1 import _analytic_section

        v = [_analytic_section(float(a), 0.12, p.Re) for a in p.alpha]
        return {"cl": np.asarray([x[0] for x in v]), "cd": np.asarray([x[1] for x in v]), "conf": np.full(n, np.nan)}
    raise ValueError(oracle)


# ------------------------------------------------------------------ statistics
def _summ(dcl: np.ndarray, ecd: np.ndarray) -> dict[str, Any]:
    if dcl.size == 0:
        return {"n": 0}
    return {
        "n": int(dcl.size),
        "median_abs_dCL": float(np.median(np.abs(dcl))),
        "rms_dCL": float(np.sqrt(np.mean(dcl**2))),
        "mean_dCL": float(np.mean(dcl)),
        "median_abs_E_CD_pct": float(np.median(np.abs(ecd))),
        "mean_E_CD_pct": float(np.mean(ecd)),
        "p90_abs_E_CD_pct": float(np.quantile(np.abs(ecd), 0.9)),
    }


def _band(re_: float) -> str | None:
    for lo, hi in RE_BANDS:
        if lo <= re_ < hi:
            return f"{lo:.0e}-{hi:.0e}"
    return None


def _spearman(a: np.ndarray, b: np.ndarray) -> float | None:
    ok = np.isfinite(a) & np.isfinite(b)
    if ok.sum() < 5:
        return None
    ra, rb = np.argsort(np.argsort(a[ok])), np.argsort(np.argsort(b[ok]))
    return float(np.corrcoef(ra, rb)[0, 1])


def validate(oracles: Iterable[str] = ORACLES, *, polars: Sequence[Polar] | None = None) -> dict[str, Any]:
    polars = list(polars) if polars is not None else load_ladson() + list(load_lsat())
    names = list(oracles)
    per: dict[str, dict[str, Any]] = {}
    for o in names:
        rows = []
        for p in polars:
            pr = predict(p, o)
            if pr is None:
                continue
            att = p.attached_mask
            for k in range(p.alpha.size):
                rows.append({
                    "tc": _geom(p)[0], "camber": _geom(p)[1], "camber_pos": _camber_pos(p),
                    "airfoil": p.airfoil, "source": p.source, "Re": p.Re, "alpha": float(p.alpha[k]),
                    "attached": bool(att[k]), "dCL": float(pr["cl"][k] - p.cl[k]),
                    "E_CD": float((p.cd[k] - pr["cd"][k]) / p.cd[k] * 100.0),
                    "conf": float(pr["conf"][k]),
                })
        per[o] = _aggregate(rows)
    return {
        "schema": VALIDATION_SCHEMA,
        "n_polars": len(polars),
        "n_airfoils": len({p.airfoil for p in polars}),
        "n_points": int(sum(p.alpha.size for p in polars)),
        "sources": sorted({p.source.split(" (")[0] for p in polars}),
        "lsat_available": lsat_available(),
        "lsat_vol4_6_skipped_no_coords": sorted(LSAT_V46_SKIPPED),
        "n_polars_by_source": {src: sum(1 for p in polars if p.source == src) for src in sorted({p.source for p in polars})},
        "criteria": {"CL_TOL": CL_TOL, "CD_TOL_PCT": CD_TOL_PCT, "attached": "alpha <= alpha(CL_max,meas)"},
        "per_oracle": per,
        "notes": ("Measured 2-D section data vs section oracles. Wind-tunnel corrections as published; "
                  "low-Re data carry tunnel-to-tunnel scatter of order 0.01-0.02 in C_d at Re<1e5. "
                  "Not FAA/EASA, not ARP6983/ED-324."),
    }


def att_n(rows: list[dict[str, Any]]) -> int:
    return sum(1 for r in rows if r["attached"])


def _aggregate(rows: list[dict[str, Any]]) -> dict[str, Any]:
    if not rows:
        return {"overall": {"n": 0}, "attached": {"n": 0}, "by_Re_band": {}, "envelope": None}
    arr = lambda key, sel: np.asarray([r[key] for r in rows if sel(r)], float)  # noqa: E731
    att = lambda r: r["attached"]  # noqa: E731
    cam = lambda r: r["attached"] and r["camber"] > SYMMETRIC_CAMBER_TOL  # noqa: E731
    by_band = {}
    for lo, hi in RE_BANDS:
        sel = lambda r, lo=lo, hi=hi: r["attached"] and lo <= r["Re"] < hi  # noqa: E731
        s = _summ(arr("dCL", sel), arr("E_CD", sel))
        if s["n"]:
            s["validated"] = s["median_abs_dCL"] <= CL_TOL and s["median_abs_E_CD_pct"] <= CD_TOL_PCT
            s["alpha_range"] = [float(arr("alpha", sel).min()), float(arr("alpha", sel).max())]
        by_band[f"{lo:.0e}-{hi:.0e}"] = s
    by_airfoil = {}
    for a in sorted({r["airfoil"] for r in rows}):
        sel = lambda r, a=a: r["attached"] and r["airfoil"] == a  # noqa: E731
        by_airfoil[a] = _summ(arr("dCL", sel), arr("E_CD", sel))
        one = next(r for r in rows if r["airfoil"] == a)
        by_airfoil[a]["tc"], by_airfoil[a]["camber"] = round(one["tc"], 4), round(one["camber"], 4)
    ok_bands = [(lo, hi) for (lo, hi) in RE_BANDS if by_band.get(f"{lo:.0e}-{hi:.0e}", {}).get("validated")]
    conf = arr("conf", att)
    err = np.abs(arr("dCL", att))
    return {
        "overall": _summ(arr("dCL", lambda r: True), arr("E_CD", lambda r: True)),
        "attached": _summ(arr("dCL", att), arr("E_CD", att)),
        "post_stall": _summ(arr("dCL", lambda r: not r["attached"]), arr("E_CD", lambda r: not r["attached"])),
        "by_Re_band": by_band,
        "by_airfoil": by_airfoil,
        "tc_range": [float(arr("tc", att).min()), float(arr("tc", att).max())] if att_n(rows) else None,
        "camber_range": [float(arr("camber", att).min()), float(arr("camber", att).max())] if att_n(rows) else None,
        "by_camber": {f"{lo:.2f}-{hi:.2f}": _summ(arr("dCL", lambda r, lo=lo, hi=hi: r["attached"] and lo <= r["camber"] < hi),
                                                   arr("E_CD", lambda r, lo=lo, hi=hi: r["attached"] and lo <= r["camber"] < hi))
                      for lo, hi in ((0.0, 0.005), (0.005, 0.02), (0.02, 0.04), (0.04, 0.07), (0.07, 1.0))},
        "camber_pos_range": ([float(arr("camber_pos", cam).min()), float(arr("camber_pos", cam).max())]
                             if any(cam(r) for r in rows) else None),
        "camber_pos_p05_p95": ([float(np.quantile(arr("camber_pos", cam), q)) for q in (0.05, 0.95)]
                               if any(cam(r) for r in rows) else None),
        "by_camber_pos": {f"{lo:.2f}-{hi:.2f}": _summ(arr("dCL", lambda r, lo=lo, hi=hi: cam(r) and lo <= r["camber_pos"] < hi),
                                                       arr("E_CD", lambda r, lo=lo, hi=hi: cam(r) and lo <= r["camber_pos"] < hi))
                          for lo, hi in ((0.0, 0.3), (0.3, 0.375), (0.375, 0.425), (0.425, 0.5), (0.5, 1.0))},
        "confidence_vs_abs_dCL_spearman": _spearman(-conf, err),
        "envelope": {
            "validated_Re_bands": [[lo, hi] for lo, hi in ok_bands],
            "validated_alpha_range": (
                [min(by_band[f"{lo:.0e}-{hi:.0e}"]["alpha_range"][0] for lo, hi in ok_bands),
                 max(by_band[f"{lo:.0e}-{hi:.0e}"]["alpha_range"][1] for lo, hi in ok_bands)]
                if ok_bands else None),
            "criteria": f"median |dCL| <= {CL_TOL} and median |E_CD| <= {CD_TOL_PCT}% over attached points",
        },
    }


def render_markdown(rep: dict[str, Any]) -> str:
    L = [
        "# Section-oracle validation vs measured polars",
        "",
        f"Schema `{rep['schema']}`. {rep['n_polars']} polars, {rep['n_airfoils']} airfoils, {rep['n_points']} points; "
        f"sources: {', '.join(rep['sources'])}. LSAT cache present: {rep['lsat_available']}.",
        "",
        "ΔC_L = pred − meas; E_CD% = (meas − pred)/meas·100 (positive = oracle under-predicts drag). "
        "Attached = α ≤ α(C_L,max) of the measured polar.",
        "",
        "## Attached-flow summary",
        "",
        "| oracle | n | median abs ΔCL | RMS ΔCL | mean ΔCL | median abs E_CD% | mean E_CD% | p90 abs E_CD% | conf↔error ρ |",
        "|---|---|---|---|---|---|---|---|---|",
    ]
    for o, s in rep["per_oracle"].items():
        a = s["attached"]
        if not a.get("n"):
            L.append(f"| `{o}` | 0 | – | – | – | – | – | – | – |")
            continue
        rho = s.get("confidence_vs_abs_dCL_spearman")
        L.append(f"| `{o}` | {a['n']} | {a['median_abs_dCL']:.3f} | {a['rms_dCL']:.3f} | {a['mean_dCL']:+.3f} | "
                 f"{a['median_abs_E_CD_pct']:.1f} | {a['mean_E_CD_pct']:+.1f} | {a['p90_abs_E_CD_pct']:.1f} | "
                 f"{'–' if rho is None else f'{rho:+.2f}'} |")
    L += ["", "## By Reynolds band (attached)", "", "| oracle | Re band | n | median abs ΔCL | median abs E_CD% | validated |",
          "|---|---|---|---|---|---|"]
    for o, s in rep["per_oracle"].items():
        for b, v in s.get("by_Re_band", {}).items():
            if v.get("n"):
                L.append(f"| `{o}` | {b} | {v['n']} | {v['median_abs_dCL']:.3f} | {v['median_abs_E_CD_pct']:.1f} | "
                         f"{'yes' if v['validated'] else 'no'} |")
    L += ["", "## Cambered sections by max-camber position p (attached, camber > 0.5% c)", "",
          "| oracle | p bin | n | median abs ΔCL | median abs E_CD% |", "|---|---|---|---|---|"]
    for o in ("gym_section", "gym_section_p04"):
        for b, v in rep["per_oracle"].get(o, {}).get("by_camber_pos", {}).items():
            if v.get("n"):
                L.append(f"| `{o}` | {b} | {v['n']} | {v['median_abs_dCL']:.3f} | {v['median_abs_E_CD_pct']:.1f} |")
    gs = rep["per_oracle"].get("gym_section", {})
    if gs.get("camber_pos_range"):
        L += ["", f"Measured p of cambered sections: range {gs['camber_pos_range'][0]:.2f}-{gs['camber_pos_range'][1]:.2f}, "
              f"5-95% {gs['camber_pos_p05_p95'][0]:.2f}-{gs['camber_pos_p05_p95'][1]:.2f}."]
    L += ["", "## Post-stall (not used for envelopes)", ""]
    for o, s in rep["per_oracle"].items():
        ps = s.get("post_stall", {})
        if ps.get("n"):
            L.append(f"- `{o}`: n={ps['n']}, median |ΔCL| {ps['median_abs_dCL']:.3f}, median |E_CD| {ps['median_abs_E_CD_pct']:.1f}%")
    L += ["", "## Worst airfoils (attached, `neuralfoil_small`, by median abs E_CD)", ""]
    ba = rep["per_oracle"].get("neuralfoil_small", {}).get("by_airfoil", {})
    worst = sorted(((k, v) for k, v in ba.items() if v.get("n")), key=lambda kv: -kv[1]["median_abs_E_CD_pct"])[:8]
    for k, v in worst:
        L.append(f"- {k}: n={v['n']}, median |ΔCL| {v['median_abs_dCL']:.3f}, median |E_CD| {v['median_abs_E_CD_pct']:.1f}%")
    L += ["", "## Envelopes", ""]
    for o, s in rep["per_oracle"].items():
        env = s.get("envelope")
        if env:
            L.append(f"- `{o}`: validated Re bands {env['validated_Re_bands'] or 'none'} ({env['criteria']}).")
    L += ["", "## Caveats", "", rep["notes"],
          "- `gym_section` is the gym's section model: NACA 4-digit at the measured t/c, max camber and max-camber position "
          "(`w.tc`, `w.camber`, `w.camber_pos`; p clipped to the gym band 0.25-0.6). Checked on every measured section with "
          "camber <= 6% c; a non-NACA section is represented by the NACA 4-digit with the same thickness, camber and p, so the "
          "remaining camber-line shape (reflex, aft loading) is a model error here. `gym_section_p04` is the same with p = 0.4. "
          "`analytic` is checked on NACA 0012 only.",
          "- `gym_section_camber_blind` is the pre-camber baseline (symmetric NACA 00xx at the measured t/c on every airfoil).",
          "- On NACA 0012 the gym section (AeroSandbox NACA 0012, open trailing edge 0.25% c) is ~0.05 high on C_L against "
          "Ladson, while the closed-TE coordinates used by `neuralfoil_small` match to 0.006: NeuralFoil is sensitive to "
          "trailing-edge thickness, and that sensitivity (not the thickness scaling) explains the NACA 0012 ΔC_L.",
          "- LSAT vols 4-6 ship no coordinates: their clean, flap-neutral polars use nominal UIUC ADS coordinates, not the "
          "measured model shape (vols 1-3 use measured coordinates). Skipped for lack of ADS coordinates: "
          + (", ".join(rep.get("lsat_vol4_6_skipped_no_coords") or []) or "none") + ". Flapped-section runs (vols 5-6) are excluded.",
          "- Ladson is tripped at 5% chord; every NeuralFoil oracle (including `gym_section`) is run with xtr = 0.05 for those "
          "polars and free transition (n_crit 9) for LSAT. The gym itself always runs free transition; with free transition "
          "the gym section is ~27% low on C_d against the tripped Ladson data, which is a test-condition mismatch, not a model error.",
          "- `analytic` (the no-NeuralFoil fallback) uses thin-airfoil C_l and a fully turbulent C_d0 = 2 C_f FF build-up "
          "(Raymer) with no lift-dependent profile drag, so it under-predicts C_d at high C_l; see analytic_fallback.md."]
    return "\n".join(L) + "\n"


def write_reports(out_dir: str | Path) -> dict[str, Any]:
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    rep = validate()
    (out / "neuralfoil_polar_validation.json").write_text(json.dumps(rep, indent=2, sort_keys=True) + "\n")
    (out / "neuralfoil_polar_validation.md").write_text(render_markdown(rep))
    return rep


if __name__ == "__main__":  # pragma: no cover
    import sys

    r = write_reports(sys.argv[1] if len(sys.argv) > 1 else "reports/validation")
    for o, s in r["per_oracle"].items():
        print(o, s["attached"])
