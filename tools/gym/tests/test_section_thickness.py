"""w.tc maps into the NeuralFoil section (symmetric NACA 00xx, exact Kulfan scaling)."""
from __future__ import annotations

import dataclasses
import json
from pathlib import Path

import numpy as np
import pytest

pytest.importorskip("neuralfoil")
asb = pytest.importorskip("aerosandbox")

from strip_uas_v0 import aero_l1, section_tc_impact, validation as v  # noqa: E402
from strip_uas_v0.teachers import neuralfoil_stub  # noqa: E402
from strip_uas_v0.wing import WingState  # noqa: E402

REP = Path(__file__).resolve().parents[1] / "reports" / "validation"


@pytest.mark.parametrize("t", [6, 9, 15, 18, 22])
def test_scaled_kulfan_is_exact_naca00xx(t):
    ref = asb.KulfanAirfoil(f"naca00{t:02d}").kulfan_parameters
    got = neuralfoil_stub.naca00_kulfan(t / 100)
    for k in ("upper_weights", "lower_weights"):
        assert np.allclose(got[k], ref[k], atol=1e-9)
    assert got["TE_thickness"] == pytest.approx(ref["TE_thickness"])


def test_thickness_changes_section_drag_and_old_path_reproducible():
    w = WingState()
    cds = [aero_l1.estimate_aero(dataclasses.replace(w, tc=t)).CD for t in (0.08, 0.12, 0.18)]
    assert cds[0] < cds[1] < cds[2]
    assert aero_l1.estimate_aero(w).CD == pytest.approx(cds[1])  # 0.12 == old default section
    with section_tc_impact._mapping(False):
        assert aero_l1.estimate_aero(dataclasses.replace(w, tc=0.18)).CD == pytest.approx(cds[1])
    assert aero_l1.MAP_SECTION_TC is True


def test_section_geometry():
    assert v.section_geometry(v.naca4_coords("0015")) == pytest.approx((0.15, 0.0), abs=1e-3)
    t, c = v.section_geometry(v.naca4_coords("4412"))
    assert t == pytest.approx(0.12, abs=3e-3) and c == pytest.approx(0.04, abs=3e-3)


def test_gym_section_only_on_symmetric_measured_sections():
    rep = json.loads((REP / "neuralfoil_polar_validation.json").read_text())
    g = rep["per_oracle"]["gym_section"]
    assert all(a["camber"] <= v.SYMMETRIC_CAMBER_TOL for a in g["by_airfoil"].values())
    assert "NACA 0012" in g["by_airfoil"]
    if rep["lsat_available"]:
        lo, hi = g["tc_range"]
        assert lo < 0.09 and hi > 0.18  # covers the gym's TC bounds (0.08-0.18) nearly fully


def test_impact_report_matches_code():
    rep = json.loads((REP / "section_tc_impact.json").read_text())
    sw = {s["tc"]: s for s in rep["tc_sweep_on_parent"]}
    assert all(s["reward_before"] == pytest.approx(0.0, abs=1e-12) for s in sw.values())
    assert sw[0.08]["reward_after"] > 0 > sw[0.18]["reward_after"]
    fresh = section_tc_impact.analyse(n_designs=20)
    assert fresh["tc_sweep_on_parent"][0]["CD_after"] == pytest.approx(sw[0.08]["CD_after"], rel=1e-9)
