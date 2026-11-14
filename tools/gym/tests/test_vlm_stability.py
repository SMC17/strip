"""Planar VLM, wing-alone static margin, stability gate, and VSPAERO geometry cross-check."""

from __future__ import annotations

import dataclasses
import math

import numpy as np
import pytest

from strip_uas_v0.env import DesignSearchEnv
from strip_uas_v0.stability import (
    CG,
    accept_stability,
    cg_for_margin,
    merge_acceptance,
    static_margin,
    vspaero_neutral_point,
)
from strip_uas_v0.teachers import vspaero_l1
from strip_uas_v0.vlm import helmbold_cla, solve
from strip_uas_v0.wing import WingState

RECT = dict(chord_root_m=0.3, taper=1.0, sweep_deg=0.0, twist_deg=0.0)
needs_vspaero = pytest.mark.skipif(not vspaero_l1.detect().available, reason="OpenVSP/VSPAERO not installed")


@pytest.mark.parametrize("ar", [4.0, 8.0, 12.0])
def test_rectangular_lift_slope_tracks_helmbold(ar):
    w = WingState(span_m=0.3 * ar, **RECT)
    v = solve(w, 4.0)
    assert v["CL_alpha_per_rad"] == pytest.approx(helmbold_cla(ar), rel=0.07)
    assert v["CL"] == pytest.approx(v["CL_alpha_per_rad"] * math.radians(4.0), rel=1e-9)


def test_unswept_rectangular_neutral_point_near_quarter_chord():
    v = solve(WingState(span_m=2.4, **RECT))
    assert 0.23 <= v["np_frac_mac"] <= 0.26


def test_sweep_back_moves_np_aft_and_cuts_lift_slope():
    out = [solve(WingState(span_m=2.4, **{**RECT, "sweep_deg": s})) for s in (0.0, 15.0, 30.0)]
    assert out[0]["x_np_m"] < out[1]["x_np_m"] < out[2]["x_np_m"]
    assert out[0]["CL_alpha_per_rad"] > out[1]["CL_alpha_per_rad"] > out[2]["CL_alpha_per_rad"]


def test_washout_gives_negative_zero_alpha_lift():
    v = solve(WingState(span_m=2.4, **{**RECT, "twist_deg": -4.0}), 0.0)
    assert v["CL"] < 0.0


def test_fixed_cg_margin_responds_to_planform():
    w = WingState()
    cg = cg_for_margin(w, 0.10)
    assert static_margin(w, cg)["static_margin"] == pytest.approx(0.10, abs=1e-9)
    aft = static_margin(dataclasses.replace(w, sweep_deg=20.0), cg)
    fwd = static_margin(dataclasses.replace(w, sweep_deg=-4.0), cg)
    assert aft["static_margin"] > 0.3 and fwd["static_margin"] < 0.0
    assert not accept_stability(aft).passed and not accept_stability(fwd).passed
    assert accept_stability(static_margin(w, cg)).passed


def test_frac_mac_cg_and_trim_report():
    s = static_margin(WingState(), CG("frac_mac", 0.15), cl_cruise=0.3)
    assert 0.05 < s["static_margin"] < 0.15
    assert s["trim"]["gated"] is False and math.isfinite(s["trim"]["CM_cg"])


def test_merge_acceptance_prefixes_and_ands():
    aero = {"passed": True, "failed_checks": [], "checks": [{"name": "CL_finite", "passed": True}]}
    bad = accept_stability({"static_margin": -0.2, "backend": "vlm_planar_v0"})
    m = merge_acceptance(aero, bad)
    assert m["passed"] is False and "stability:static_margin_in_band" in m["failed_checks"]
    assert m["checks"][0]["name"] == "CL_finite"


def test_env_stability_gate_rejects_unstable_children_and_claim_reports_margin():
    env = DesignSearchEnv(parent=WingState(), max_steps=30, seed=0, stability_gate=True)
    env.reset(seed=0)
    sweep_fwd = np.array([0, 0, 0, -1.0, 0, 0, 0], dtype=float)
    infos = [env.step(sweep_fwd)[4] for _ in range(4)]
    gated = [i for i in infos if not i.get("rejected")]
    assert gated and "stability" in gated[-1]
    assert any("stability:static_margin_in_band" in i["acceptance"]["failed_checks"] for i in gated)
    claim = env.claim_done(require_improvement=False)
    assert "static_margin" in claim["measured"] and claim["stability"]["cg"]["mode"] == "fixed"


def test_env_without_gate_unchanged():
    env = DesignSearchEnv(parent=WingState(), max_steps=3, seed=0)
    env.reset(seed=0)
    info = env.step(np.zeros(7))[4]
    assert "stability" not in info
    assert not any(c["name"].startswith("stability:") for c in info["acceptance"]["checks"])


@needs_vspaero
@pytest.mark.parametrize("kw", [dict(taper=1.0, sweep_deg=0.0), dict(taper=1.0, sweep_deg=30.0),
                                dict(taper=0.5, sweep_deg=20.0)])
def test_vspaero_geometry_matches_wingstate(kw):
    """Regression: VSPAERO built a wing with twice the span (per-side XSec Area got the total).

    Two independent VLMs (VSPAERO, in-repo numpy) must agree on lift slope and neutral point.
    """
    w = WingState(span_m=2.4, chord_root_m=0.3, twist_deg=0.0, **kw)
    vs = vspaero_neutral_point(w)
    v = solve(w)
    assert vs is not None
    assert vs["CL_alpha_per_rad"] == pytest.approx(v["CL_alpha_per_rad"], rel=0.05)
    assert abs(vs["x_np_m"] - v["x_np_m"]) / w.mac_m() < 0.08
