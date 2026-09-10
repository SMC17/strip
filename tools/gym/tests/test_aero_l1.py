from strip_uas_v0.aero_l1 import estimate_aero
from strip_uas_v0.wing import WingState


def test_analytic_aero_positive_ld():
    a = estimate_aero(WingState(), prefer_neuralfoil=False)
    assert a.CD > 0
    assert a.LD > 0
    assert a.neuralfoil_used is False
    assert a.vspaero_used is False
    assert "analytic" in a.fidelity


def test_neuralfoil_path_or_fallback():
    a = estimate_aero(WingState(), prefer_neuralfoil=True)
    assert a.CD > 0
    assert a.fidelity in ("L1_analytic_polar", "L1_neuralfoil_section")
    assert a.vspaero_used is False
