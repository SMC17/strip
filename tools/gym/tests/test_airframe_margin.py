import dataclasses
import math

import numpy as np
import pytest

from strip_uas_v0.airframe import MODES, TR711_KF, Airframe, datcom_lift_slope, k_f, neutral_point, resolve
from strip_uas_v0.env import DesignSearchEnv
from strip_uas_v0.stability import CG, accept_stability, cg_for_margin, static_margin
from strip_uas_v0.wing import WingState

W = WingState()


def test_kf_table_matches_digitised_tr711_points_and_flags_range():
    for x, y in TR711_KF:
        assert k_f(x) == (pytest.approx(y), True)
    assert k_f(5.0)[1] is False and k_f(70.0)[1] is False
    assert np.all(np.diff([y for _, y in TR711_KF]) > 0)  # monotone, as in fig. 8


def test_datcom_slope_limits():
    assert datcom_lift_slope(1e4) == pytest.approx(2 * math.pi, rel=1e-3)
    assert datcom_lift_slope(4.0) < datcom_lift_slope(8.0) < 2 * math.pi
    assert datcom_lift_slope(4.0, 30.0) < datcom_lift_slope(4.0)


def test_wing_only_mode_is_unchanged():
    a = static_margin(W, CG("frac_mac", 0.2))
    b = static_margin(W, CG("frac_mac", 0.2), airframe=Airframe(mode="wing_only"))
    assert a["static_margin"] == pytest.approx(b["static_margin"]) and a["configuration"] == "wing_only"


def test_tail_moves_np_aft_by_textbook_amount_and_fuselage_forward():
    t = neutral_point(W, Airframe.default_for(W, "wing_tail"))
    assert t["tail_volume"] == pytest.approx(0.5, rel=1e-6)
    a_w, a_te, mac = t["CL_alpha_wing_per_rad"], t["tail_effective_slope_per_rad"], t["mac_m"]
    lt = Airframe.default_for(W).tail_x_ac_m - t["x_np_wing_m"]
    assert t["np_shift_tail_mac"] == pytest.approx(a_te * lt / (a_w + a_te) / mac, rel=1e-9)
    assert 0.15 < t["np_shift_tail_mac"] < 0.3
    f = neutral_point(W, Airframe.default_for(W))
    assert f["x_np_m"] < t["x_np_m"] and f["np_shift_fuselage_mac"] < 0
    aft = neutral_point(W, Airframe.default_for(W, wing_pos_frac=0.45))
    assert aft["np_shift_fuselage_mac"] < f["np_shift_fuselage_mac"]  # wing further aft on body -> larger K_f


def test_margin_and_gate_by_mode():
    cg = CG("frac_mac", 0.25)
    sm = {m: static_margin(W, cg, airframe=resolve(m, W))["static_margin"] for m in MODES}
    assert sm["wing_only"] < sm["wing_tail_fuselage"] < sm["wing_tail"]
    assert not accept_stability(static_margin(W, cg)).passed
    assert accept_stability(static_margin(W, cg, airframe=resolve("wing_tail_fuselage", W))).passed
    af = resolve("wing_tail_fuselage", W)
    c = cg_for_margin(W, 0.12, airframe=af)
    assert static_margin(W, c, airframe=af)["static_margin"] == pytest.approx(0.12, abs=1e-9)


def test_env_stability_gate_with_airframe():
    env = DesignSearchEnv(parent=W, prefer_neuralfoil=False, stability_gate=True, airframe="wing_tail_fuselage", max_steps=2)
    env.reset(seed=0)
    _, r, *_, info = env.step(np.zeros(env.action_space.shape, dtype=np.float32))
    st = info.get("stability")
    assert st["configuration"] == "wing_tail_fuselage"
    assert st["static_margin"] == pytest.approx(env.sm_target, abs=1e-6)
