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
    assert len(w.as_vector()) == 8 and WingState.from_vector(w.as_vector()) == w
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
