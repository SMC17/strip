"""Section-oracle validation against measured polars (Ladson always; LSAT if fetched)."""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pytest

from strip_uas_v0 import validation as v

nf = pytest.importorskip("neuralfoil")
REPORT = Path(__file__).resolve().parents[1] / "reports" / "validation" / "neuralfoil_polar_validation.json"


def test_ladson_vendored_and_sane():
    pols = v.load_ladson()
    assert pols and all(p.Re == pytest.approx(6.0e6) and p.tripped for p in pols)
    p = pols[0]
    assert 0.005 < float(np.min(p.cd)) < 0.01  # NACA 0012, Re 6e6, tripped
    assert np.all(np.diff(p.alpha) > 0)


def test_naca4_coords_closed_and_thick():
    c = v.naca4_coords("0012")
    assert c[0, 0] == pytest.approx(1.0, abs=1e-6) and c[-1, 0] == pytest.approx(1.0, abs=1e-6)
    assert float(np.ptp(c[:, 1])) == pytest.approx(0.12, abs=0.003)


def test_neuralfoil_matches_ladson_tripped():
    rep = v.validate(("neuralfoil_small", "gym_section"), polars=v.load_ladson())
    for o in ("neuralfoil_small", "gym_section"):
        att = rep["per_oracle"][o]["attached"]
        assert att["n"] > 20
        assert att["median_abs_E_CD_pct"] < 10.0
        assert att["median_abs_dCL"] < 0.08


def test_analytic_fallback_is_flagged_unvalidated():
    rep = v.validate(("analytic",), polars=v.load_ladson())
    assert rep["per_oracle"]["analytic"]["envelope"]["validated_Re_bands"] == []


@pytest.mark.skipif(not v.lsat_available(), reason="UIUC LSAT not fetched (python data/fetch/fetch_strip_data.py)")
def test_lsat_low_re_envelope():
    pols = list(v.load_lsat())
    assert len(pols) > 300
    rep = v.validate(("neuralfoil_small",), polars=pols)
    bands = rep["per_oracle"]["neuralfoil_small"]["by_Re_band"]
    assert bands["2e+05-6e+05"]["validated"] is True
    assert bands["0e+00-1e+05"]["validated"] is False


def test_committed_report_consistent():
    rep = json.loads(REPORT.read_text())
    assert rep["schema"] == v.VALIDATION_SCHEMA
    assert rep["lsat_available"] is True and rep["n_polars"] > 300
    env = rep["per_oracle"]["neuralfoil_small"]["envelope"]
    assert [2.0e5, 5.5e5] in env["validated_Re_bands"]


def test_ads_coords_lednicer_and_selig(tmp_path):
    sel = tmp_path / "s.dat"
    sel.write_text("X\n1.0 0.0\n0.5 0.05\n0.0 0.0\n0.5 -0.05\n1.0 0.0\n")
    led = tmp_path / "l.dat"
    led.write_text("X\n3. 3.\n\n0.0 0.0\n0.5 0.05\n1.0 0.0\n\n0.0 0.0\n0.5 -0.05\n1.0 0.0\n")
    a, b = v.parse_ads_coords(sel), v.parse_ads_coords(led)
    assert a.shape == b.shape == (5, 2) and np.allclose(a, b)


@pytest.mark.parametrize("name,comment,key", [
    ("E387 (E)", "clean", "e387"), ("FX 63-137 (C)", "Clean", "fx63137"),
    ("W1011-20 f0", "Clean, Cf/C = 20%, Flap = 0\xb0", "w1011"), ("W1011-20 fp10", "Clean, Cf/C = 20%, Flap = 10\xb0", None),
    ("S9000 fp0", "Clean, Flap = 0\xb0", "s9000"), ("S9000 fp2.5", "Clean, Flap = 2.5\xb0", None),
    ("E387 (E)", "u.s.t. located at 2% chord, l.s.t. located at 5% chord", None), ("S834", "clean", None),
])
def test_lsat_v46_selection(name, comment, key):
    assert v._lsat_v46_key(name, comment) == key


@pytest.mark.skipif(not (v.lsat_dir() / "volume05").is_dir(), reason="LSAT vols 4-6 not fetched")
def test_lsat_v46_loaded_and_comparable():
    ps = [p for p in v.load_lsat() if p.source[-2:] in ("04", "05", "06")]
    assert len(ps) >= 80 and len({p.airfoil for p in ps}) >= 15
    assert all(p.meta["coords"].startswith("nominal") for p in ps)
    r = v.validate(("neuralfoil_small",), polars=ps)["per_oracle"]["neuralfoil_small"]["attached"]
    assert r["median_abs_dCL"] < 0.08 and r["median_abs_E_CD_pct"] < 12.0
