"""Multi-point mission reward (cruise / climb / loiter) for Strip-UAS-v0."""

from __future__ import annotations

import dataclasses

import numpy as np
import pytest

from strip_uas_v0.aero_l1 import G, RHO_SL
from strip_uas_v0.env import DesignSearchEnv
from strip_uas_v0.mission import Mission, MissionPoint, evaluate_mission, mission_score, trim
from strip_uas_v0.wing import WingState

W = WingState()


@pytest.mark.parametrize("nf", [False, True])
def test_trim_hits_required_cl(nf):
    out = evaluate_mission(W, prefer_neuralfoil=nf)
    for r in out:
        assert r["trimmed"] and r["accepted"]
        assert r["CL"] == pytest.approx(r["CL_req"], abs=0.01)
        q = 0.5 * RHO_SL * r["V_mps"] ** 2
        assert r["CL_req"] == pytest.approx(5.0 * G / (q * W.area_m2()))
    # slower points need more lift
    assert out[0]["CL_req"] < out[1]["CL_req"] < out[2]["CL_req"]


def test_identical_wing_scores_zero():
    m = mission_score(W, W, prefer_neuralfoil=False)
    assert m["score"] == pytest.approx(0.0, abs=1e-12) and m["accepted"]


def test_multipoint_exposes_cruise_loss_that_mean_hides():
    """Higher-AR wing (span 2.4->3.0 m, ~same area): loiter/climb improve, cruise L/D drops (analytic L1 polar)."""
    child = dataclasses.replace(W, span_m=3.0, chord_root_m=0.25)
    m = mission_score(child, W, prefer_neuralfoil=False)
    d = {r["name"]: r["d"] for r in m["points"]}
    assert d["cruise"] < 0 < d["loiter"]
    assert m["worst_point"] == "cruise"
    assert m["score"] == pytest.approx(m["mean_d"] + m["worst_d"])
    assert m["score"] < m["mean_d"]


def test_untrimmable_point_not_credited():
    heavy = Mission(mass_kg=60.0)
    m = mission_score(W, W, heavy, prefer_neuralfoil=False)
    loiter = [r for r in m["points"] if r["name"] == "loiter"][0]
    assert loiter["credited"] is False and loiter["child"]["reason"] == "CL_req_outside_alpha_band"
    assert m["accepted"] is False


def test_trim_reports_band_failure_explicitly():
    t = trim(W, 5.0, 10.0, prefer_neuralfoil=False)
    assert t["trimmed"] is False and t["reason"] == "CL_req_outside_alpha_band"


def test_climb_metric_is_power_lower_is_better():
    m = Mission(points=(MissionPoint("climb", 16.0, "climb"),))
    better = dataclasses.replace(W, span_m=3.0, chord_root_m=0.22)
    out = mission_score(better, W, m, prefer_neuralfoil=False)
    r = out["points"][0]
    assert r["child"]["value"] < r["parent"]["value"] and r["d"] > 0


def test_bad_metric_rejected():
    with pytest.raises(ValueError):
        MissionPoint("x", 10.0, "speed")


def test_env_mission_reward_and_info():
    env = DesignSearchEnv(parent=W, max_steps=3, seed=0, prefer_neuralfoil=False, mission=Mission())
    env.reset(seed=0)
    _, r0, _, _, i0 = env.step(np.zeros(7))
    assert r0 == pytest.approx(0.0, abs=1e-12)
    assert [p["name"] for p in i0["mission"]["points"]] == ["cruise", "climb", "loiter"]
    _, r1, _, _, i1 = env.step(np.array([1.0, -1.0, 0, 0, 0, 0, 0]))
    assert r1 == pytest.approx(i1["mission"]["score"])
    score, acc = env.candidate_reward(dataclasses.replace(W, span_m=2.5))
    assert acc["passed"] and score != -1.0
