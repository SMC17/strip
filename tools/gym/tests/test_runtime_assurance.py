"""Strip mirror of the Simplex-style RTA: L0 / static-margin monitor, scaling fallback, fault hooks."""

from __future__ import annotations

import json

import numpy as np
import pytest

from strip_uas_v0.env import DesignSearchEnv
from strip_uas_v0.faults import Fault, FaultInjector
from strip_uas_v0.monitors import monitor_action
from strip_uas_v0.runtime_assurance import LABEL, DesignSimplex, FaultyObservation, Simplex, Verdict
from strip_uas_v0.wing import WingState


def test_simplex_switch_log():
    flags = iter([True, False, True, False, False, True])
    s = Simplex(lambda c, a: Verdict(next(flags)), recovery_steps=1)
    used = [s.decide(t, None, "adv", "fb")[0] for t in range(6)]
    assert used == ["adv", "fb", "adv", "fb", "fb", "adv"]
    assert s.summary()["n_switches_to_fallback"] == 2 and s.summary()["label"] == LABEL


def test_l0_rejected_action_is_scaled_not_penalised(tmp_path):
    parent = WingState(sweep_deg=34.0)  # 1.5 deg/step: +1 → 35.5 > 35 band
    env = DesignSearchEnv(parent=parent, max_steps=5, seed=0, prefer_neuralfoil=False,
                          evidence_dir=str(tmp_path))
    rta = DesignSimplex(env)
    rta.reset(seed=0)
    a = np.array([0, 0, 0, 1.0, 0, 0, 0])
    assert not monitor_action(env.state, list(a)).allow
    _, reward, _, _, info = rta.step(a)
    assert info["rta"]["substituted"] and info["rta"]["fallback_scale"] == 0.5
    assert not info["rejected"] and reward != -1.0
    assert env.state.sweep_deg == pytest.approx(34.75)
    recs = [p for p in env.evidence_packs if p.get("type") == "rta_intervention"]
    assert len(recs) == 1 and recs[0]["proposed_action"] == a.tolist()
    assert any("rta_intervention" in f.read_text() for f in tmp_path.glob("*.json"))


def test_stability_monitor_blocks_margin_breaking_sweep():
    env = DesignSearchEnv(parent=WingState(), max_steps=10, seed=0, prefer_neuralfoil=False)
    rta = DesignSimplex(env, stability=True)
    rta.reset(seed=0)
    fwd = np.array([0, 0, 0, -1.0, 0, 0, 0])
    infos = [rta.step(fwd)[4] for _ in range(4)]
    assert any(i["rta"]["substituted"] for i in infos)
    assert any(r.startswith("stability:") for i in infos for r in i["rta"]["reasons"])
    from strip_uas_v0.stability import accept_stability, static_margin

    assert accept_stability(static_margin(env.state, rta._cg)).passed  # executed design stayed in band
    assert rta.summary()["stability_monitor"] is True


def test_faulty_observation_freeze_looks_valid():
    env = DesignSearchEnv(parent=WingState(), max_steps=5, seed=0, prefer_neuralfoil=False)
    inj = FaultInjector([Fault("freeze", "obs", 0.0, 1.0, 3.0)])
    w = FaultyObservation(env, inj)
    o0, _ = w.reset(seed=0)
    o1, *_ = w.step(np.full(7, 0.5))
    assert np.allclose(o1, o0)  # stale, but no dropout flag
    o3, *_ = w.step(np.full(7, 0.5))
    o3, *_ = w.step(np.full(7, 0.5))
    assert not np.allclose(o3, o0)
    assert json.dumps(inj.summary())
