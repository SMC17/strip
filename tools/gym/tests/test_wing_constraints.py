from strip_uas_v0.wing import WingState, evaluate_l0


def test_default_feasible():
    r = evaluate_l0(WingState())
    assert r.feasible, r.violations


def test_bad_taper_rejected():
    h = WingState(taper=0.1)
    r = evaluate_l0(h)
    assert not r.feasible
    assert any("taper" in v for v in r.violations)


def test_bad_ar_rejected():
    # very stubby wing
    h = WingState(span_m=0.5, chord_root_m=0.5, taper=1.0)
    r = evaluate_l0(h)
    assert not r.feasible
    assert any("AR" in v for v in r.violations)
