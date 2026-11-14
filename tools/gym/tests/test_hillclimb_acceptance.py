"""Hill-climb look-ahead applies the same acceptance gate as env.step."""

from __future__ import annotations

import numpy as np

from strip_uas_v0 import env as env_mod
from strip_uas_v0.env import DesignSearchEnv
from strip_uas_v0.monitors import monitor_action
from strip_uas_v0.search import hillclimb_policy_factory


def _feasible_proposal(env):
    rng = np.random.default_rng(0)
    for _ in range(200):
        d = monitor_action(env.state, rng.uniform(-0.3, 0.3, 7))
        if d.allow and d.projected is not None:
            return d.projected
    raise AssertionError("no feasible proposal")


def test_candidate_reward_gates_out_of_envelope(monkeypatch):
    env = DesignSearchEnv(max_steps=4, seed=0)
    env.reset(seed=0)
    w = _feasible_proposal(env)
    score, acc = env.candidate_reward(w)
    assert acc["passed"] and score > -1.0

    real = env_mod.estimate_aero

    def bad_cd(wing, **kw):
        a = real(wing, **kw)
        if wing is w:
            a.CD = 10.0  # implausible: must fail CD_plausible
            a.LD = a.CL / a.CD
        return a

    monkeypatch.setattr(env_mod, "estimate_aero", bad_cd)
    score, acc = env.candidate_reward(w)
    assert score == -1.0 and not acc["passed"]
    assert "CD_plausible" in acc["failed_checks"]


def test_candidate_reward_uses_same_fidelity_parent(monkeypatch):
    # Even when the env's own parent is VSPAERO, proposals compare cheap-vs-cheap.
    env = DesignSearchEnv(max_steps=4, seed=0)
    env.reset(seed=0)
    env.parent_aero_fidelity = "L1_vspaero"  # simulate a VSPAERO parent
    w = _feasible_proposal(env)
    score, acc = env.candidate_reward(w)
    assert acc["passed"], acc["failed_checks"]


def test_hillclimb_never_picks_gated_candidate(monkeypatch):
    env = DesignSearchEnv(max_steps=4, seed=0)
    env.reset(seed=0)
    calls = {"n": 0}

    def all_fail(w):
        calls["n"] += 1
        return -1.0, {"passed": False, "failed_checks": ["forced"]}

    monkeypatch.setattr(env, "candidate_reward", all_fail)
    policy = hillclimb_policy_factory(np.random.default_rng(1))
    a = policy(None, env)
    assert a.shape == (9,)
    assert calls["n"] >= 1
