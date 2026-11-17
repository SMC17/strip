import dataclasses

import pytest

from strip_uas_v0.airframe import Airframe, neutral_point as analytic_np
from strip_uas_v0.teachers import vspaero_l1
from strip_uas_v0.teachers import vspaero_config as vc
from strip_uas_v0.wing import WingState


def test_tail_block_rendered_without_vspaero():
    w = WingState()
    af = Airframe.default_for(w, "wing_tail")
    tail = vc.tail_geometry(af, z_frac_span=0.1)
    assert tail["chord"] * tail["span"] == pytest.approx(af.tail_area_m2)
    assert tail["x_le"] + 0.25 * tail["chord"] == pytest.approx(af.tail_x_ac_m)
    params = vspaero_l1._wing_params(alpha_deg=2.0, span_m=w.span_m, chord_root_m=w.chord_root_m,
                                     taper=w.taper, sweep_deg=w.sweep_deg, twist_deg=w.twist_deg)
    body = vc._render(params, tail)
    assert 'SetGeomName( tail_id, "HTail" )' in body
    assert "PLACEHOLDER" not in body
    assert "HTail" not in vc._render(params, None)


needs_vsp = pytest.mark.skipif(not vspaero_l1.detect().available, reason="VSPAERO not available")


@needs_vsp
@pytest.mark.parametrize("sweep", [5.0, 20.0])
def test_vspaero_tail_np_agrees_with_analytic(sweep):
    w = dataclasses.replace(WingState(), sweep_deg=sweep)
    af = Airframe.default_for(w, "wing_tail")
    v = vc.neutral_point(w, af)
    assert v is not None
    a = analytic_np(w, af)
    assert abs(a["x_np_m"] - v["x_np_m"]) / w.mac_m() < 0.03
    vw = vc.neutral_point(w, None)
    assert v["x_np_m"] - vw["x_np_m"] > 0.15 * w.mac_m()  # tail moves NP aft
