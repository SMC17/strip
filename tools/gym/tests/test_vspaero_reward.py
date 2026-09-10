"""VSPAERO in DesignSearchEnv reward (mock + optional real)."""

from __future__ import annotations


import numpy as np
import pytest

from strip_uas_v0.aero_l1 import estimate_aero
from strip_uas_v0.env import DesignSearchEnv, _reward
from strip_uas_v0.teachers import vspaero_l1
from strip_uas_v0.wing import WingState


def _fake_vspaero_ok(cl=0.35, cd=0.02, cm=-0.04):
    def _run_for_wing(wing, **kwargs):
        return {
            "teacher": "vspaero_l1",
            "skipped": False,
            "skip_reason": None,
            "fidelity": vspaero_l1.FIDELITY,
            "CL": cl,
            "CD": cd,
            "CM": cm,
            "LD": cl / cd,
            "alpha_deg": wing.alpha_deg,
            "notes": "mock vspaero",
        }

    return _run_for_wing


def test_estimate_aero_vspaero_mock(monkeypatch):
    fake_avail = vspaero_l1.VSPAEROAvailability(
        vspscript="/fake/vspscript", vspaero="/fake/vspaero", version="mock"
    )
    monkeypatch.setattr(vspaero_l1, "detect", lambda: fake_avail)
    monkeypatch.setattr(vspaero_l1, "run_for_wing", _fake_vspaero_ok(0.4, 0.025))

    a = estimate_aero(WingState(), prefer_vspaero=True, prefer_neuralfoil=False)
    assert a.vspaero_used is True
    assert a.fidelity == "L1_vspaero_vlm"
    assert a.CL == pytest.approx(0.4)
    assert a.CD == pytest.approx(0.025)
    assert a.LD == pytest.approx(16.0)


def test_estimate_aero_vspaero_skips_to_cheap(monkeypatch):
    monkeypatch.setattr(
        vspaero_l1, "detect", lambda: vspaero_l1.VSPAEROAvailability()
    )
    a = estimate_aero(WingState(), prefer_vspaero=True, prefer_neuralfoil=False)
    assert a.vspaero_used is False
    assert "analytic" in a.fidelity
    assert a.LD > 0


def test_env_reward_records_vspaero_fidelity(monkeypatch):
    fake_avail = vspaero_l1.VSPAEROAvailability(
        vspscript="/fake/vspscript", vspaero="/fake/vspaero", version="mock"
    )
    monkeypatch.setattr(vspaero_l1, "detect", lambda: fake_avail)

    # Parent slightly worse L/D than child mock
    calls = {"n": 0}

    def _run_for_wing(wing, **kwargs):
        calls["n"] += 1
        # Vary slightly with span so reward can change
        cl = 0.30 + 0.02 * (wing.span_m - 2.0)
        cd = 0.022
        return {
            "teacher": "vspaero_l1",
            "skipped": False,
            "skip_reason": None,
            "fidelity": vspaero_l1.FIDELITY,
            "CL": cl,
            "CD": cd,
            "CM": -0.03,
            "LD": cl / cd,
            "alpha_deg": wing.alpha_deg,
            "notes": "mock",
        }

    monkeypatch.setattr(vspaero_l1, "run_for_wing", _run_for_wing)

    env = DesignSearchEnv(
        parent=WingState(),
        max_steps=3,
        seed=0,
        prefer_neuralfoil=False,
        prefer_vspaero=True,
    )
    obs, info = env.reset()
    assert info["prefer_vspaero"] is True
    assert info["parent_aero_fidelity"] == "L1_vspaero_vlm"

    obs2, reward, term, trunc, info2 = env.step(np.array([0.05, 0, 0, 0, 0, 0, 0]))
    assert info2["rejected"] is False
    assert info2["vspaero_used"] is True
    assert info2["fidelity"] == "L1_vspaero_vlm"
    assert isinstance(reward, float)
    assert len(env.evidence_packs) >= 1
    pack = env.evidence_packs[-1]
    assert pack["aero"]["vspaero_used"] is True
    assert pack["aero"]["fidelity"] == "L1_vspaero_vlm"
    claim_ids = {c["id"] for c in pack["claims"]}
    assert "vspaero_vlm" in claim_ids
    assert pack["odd"]["limits"]["vspaero_reward_exploratory_only"] is True
    assert calls["n"] >= 2  # parent + step (+ maybe obs)


def test_reward_uses_parent_cd_term():
    w = WingState()
    # Cheap path: just ensure API accepts parent_cd
    r = _reward(w, parent_ld=10.0, parent_area=w.area_m2(), prefer_neuralfoil=False, parent_cd=0.05)
    assert isinstance(r, float)


def test_env_vspaero_real_if_vendor(tmp_path):
    avail = vspaero_l1.detect()
    if not avail.available:
        pytest.skip("vspscript/vspaero not available")
    env = DesignSearchEnv(
        parent=WingState(),
        max_steps=1,
        seed=1,
        prefer_neuralfoil=False,
        prefer_vspaero=True,
        evidence_dir=str(tmp_path),
    )
    env.reset()
    # Tiny action so L0 accepts
    _, reward, _, _, info = env.step(np.zeros(7))
    assert info["rejected"] is False
    assert info["vspaero_used"] is True
    assert info["fidelity"] == "L1_vspaero_vlm"
    assert info["CL"] is not None and abs(info["CL"]) > 0.01
    assert info["CD"] is not None and info["CD"] > 0
    assert env.evidence_packs[0]["aero"]["vspaero_used"] is True
