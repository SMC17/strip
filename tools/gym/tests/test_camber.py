"""Camber as a design parameter (NACA 4-digit, max camber at 0.4 c)."""
from __future__ import annotations

import json
import math
from pathlib import Path

import numpy as np
import pytest

from strip_uas_v0 import aero_l1
from strip_uas_v0.monitors import apply_action
from strip_uas_v0.wing import WingState, evaluate_l0

REP = Path(__file__).resolve().parents[1] / "reports" / "validation" / "neuralfoil_polar_validation.json"


def test_thin_airfoil_zero_lift_angle_naca2412():
    # Thin-airfoil theory for the NACA 2412 mean line: alpha_L0 = -2.08 deg (Anderson, Example 4.6)
    assert math.degrees(aero_l1.zero_lift_alpha_naca4(0.02, 0.4)) == pytest.approx(-2.08, abs=0.02)
    assert aero_l1.zero_lift_alpha_naca4(0.0) == 0.0


def test_symmetric_kulfan_unchanged():
    pytest.importorskip("aerosandbox")
    from strip_uas_v0.teachers import neuralfoil_stub as ns

    a, b = ns.naca4_kulfan(0.12, 0.0), ns.naca00_kulfan(0.12)
    for k in a:
        assert np.allclose(a[k], b[k])


def test_camber_raises_lift_at_fixed_alpha_both_paths():
    pytest.importorskip("neuralfoil")
    w0, w2 = WingState(), WingState(camber=0.02)
    for nf in (True, False):
        assert aero_l1.estimate_aero(w2, prefer_neuralfoil=nf).CL > aero_l1.estimate_aero(w0, prefer_neuralfoil=nf).CL + 0.15


def test_action_vector_and_backward_compat():
    w = WingState(camber=0.02)
    assert len(w.as_vector()) == 9 and WingState.from_vector(w.as_vector()) == w
    assert apply_action(w, [0.0] * 7).camber == pytest.approx(0.02)  # 7-dim agents leave camber alone
    assert apply_action(w, [0.0] * 7 + [1.0]).camber == pytest.approx(0.025)
    assert apply_action(WingState(), [0.0] * 7 + [-1.0]).camber == 0.0


def test_l0_camber_band():
    assert evaluate_l0(WingState(camber=0.04)).feasible
    assert any(v.startswith("camber_out_of_band") for v in evaluate_l0(WingState(camber=0.065)).violations)


def test_cambered_gym_section_beats_symmetric_baseline():
    r = json.loads(REP.read_text())["per_oracle"]
    g, blind = r["gym_section"]["attached"], r["gym_section_camber_blind"]["attached"]
    assert g["n"] > 1000
    assert g["median_abs_dCL"] < 0.1 and g["median_abs_dCL"] < blind["median_abs_dCL"] / 2


def test_camber_position_parameter():
    from strip_uas_v0 import aero_l1
    from strip_uas_v0.wing import CAMBER_POS, evaluate_l0

    w = WingState(camber=0.02, camber_pos=0.3)
    assert len(w.as_vector()) == 9 and WingState.from_vector(w.as_vector()) == w
    assert WingState.from_vector(w.as_vector()[:8]).camber_pos == CAMBER_POS  # 8-dim vectors keep the default
    assert apply_action(w, [0.0] * 8).camber_pos == pytest.approx(0.3)
    assert apply_action(w, [0.0] * 8 + [1.0]).camber_pos == pytest.approx(0.32)
    assert evaluate_l0(w).feasible
    assert any(v.startswith("camber_pos_out_of_band") for v in evaluate_l0(WingState(camber=0.02, camber_pos=0.7)).violations)
    # thin-airfoil zero-lift angle grows in magnitude as max camber moves aft (Anderson eq. 4.61)
    a = [aero_l1.zero_lift_alpha_naca4(0.02, p) for p in (0.25, 0.4, 0.6)]
    assert a[0] > a[1] > a[2]
    cl = [aero_l1.estimate_aero(WingState(camber=0.02, camber_pos=p), prefer_neuralfoil=False).CL for p in (0.25, 0.6)]
    assert cl[1] > cl[0]


def test_camber_position_validation_report():
    import json
    from pathlib import Path

    rep = json.loads((Path(__file__).resolve().parents[1] / "reports" / "validation" / "neuralfoil_polar_validation.json").read_text())
    g, g4 = rep["per_oracle"]["gym_section"], rep["per_oracle"]["gym_section_p04"]
    assert g["attached"]["n"] == g4["attached"]["n"] > 1000
    lo, hi = g["camber_pos_p05_p95"]
    assert 0.25 <= lo < 0.4 < hi <= 0.6
    assert g["attached"]["median_abs_dCL"] < 0.08  # still near NeuralFoil's own floor


def test_applicability_flags_camber_pos_outside_measured():
    from strip_uas_v0 import applicability as ap
    from strip_uas_v0.aero_l1 import estimate_aero

    w = WingState(camber=0.03, camber_pos=0.58)
    names = {c[0]: c[1] for c in ap.assess(estimate_aero(w), wing=w)["checks"]}
    if "section_camber_pos_in_measured_range" not in names:
        pytest.skip("NeuralFoil not installed (analytic path has no section-range checks)")
    assert names["section_camber_pos_in_measured_range"] is False
    w2 = WingState(camber=0.03, camber_pos=0.4)
    assert {c[0]: c[1] for c in ap.assess(estimate_aero(w2), wing=w2)["checks"]}["section_camber_pos_in_measured_range"]
