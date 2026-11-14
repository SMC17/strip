"""Strip-UAS-v0 acceptance gate, measure-then-claim, evidence v2 provenance."""

from __future__ import annotations

import numpy as np

from strip_uas_v0.acceptance import accept_aero, is_accepted
from strip_uas_v0.aero_l1 import estimate_aero
from strip_uas_v0.env import DesignSearchEnv
from strip_uas_v0.provenance import OptimizerRecord, canonical_digest, verify_log
from strip_uas_v0.search import run_search
from strip_uas_v0.strip_assurance import strip_overlay
from strip_uas_v0.wing import WingState, evaluate_l0


def test_default_wing_passes_gate():
    acc = accept_aero(estimate_aero(WingState(), prefer_neuralfoil=False))
    assert acc.passed, acc.to_dict()


def test_analytic_cl_clamp_is_rejected():
    w = WingState(alpha_deg=12.0, twist_deg=4.0)
    assert evaluate_l0(w).feasible
    a = estimate_aero(w, prefer_neuralfoil=False)
    acc = accept_aero(a)
    assert not acc.passed
    assert "CL_not_clamped" in acc.failed_checks or "alpha_in_attached_band" in acc.failed_checks


def test_mixed_fidelity_vs_parent_is_rejected():
    a = estimate_aero(WingState(), prefer_neuralfoil=False)
    assert not accept_aero(a, parent_fidelity="L1_vspaero_vlm").passed
    assert accept_aero(a, parent_fidelity=a.fidelity).passed


def test_overlay_rejects_failed_gate():
    ov = strip_overlay({"monitor": {"allow": True}, "l0": {"feasible": True},
                        "aero": {"CL": 0.5}, "acceptance": {"passed": False}})
    assert ov["disposition"] == "reject_acceptance_gate"
    assert not is_accepted({"acceptance": {"passed": False}})


def _episode(seed=5, steps=4):
    opt = OptimizerRecord(implementation="test.fixed", version="1", max_evals=steps).start()
    env = DesignSearchEnv(parent=WingState(), max_steps=steps, seed=seed,
                          prefer_neuralfoil=False, optimizer=opt)
    env.reset(seed=seed)
    a = np.zeros(7, dtype=np.float32)
    a[0] = 0.2  # more span -> higher AR -> better L/D in L1
    for _ in range(steps):
        env.step(a)
    return env


def test_step_and_pack_carry_acceptance_and_provenance():
    env = _episode()
    pack = env.evidence_packs[-1]
    assert pack["schema"] == "strip_uas_v0.evidence.v2"
    assert pack["acceptance"]["schema"] == "strip_uas_v0.acceptance.v1"
    assert pack["harness"]["name"] == "strip_uas_v0"
    assert pack["optimizer"]["budget"]["max_evals"] == 4
    assert pack["seeds"]["base_seed"] == 5


def test_claim_done_fresh_measurement():
    env = _episode()
    ld = estimate_aero(env.state, prefer_neuralfoil=False).LD
    ok = env.claim_done({"LD": ld})
    assert ok["improved"] and ok["accepted"], ok["reasons"]
    lie = env.claim_done({"LD": ld * 1.2})
    assert not lie["accepted"] and any(r.startswith("claim_mismatch") for r in lie["reasons"])


def test_deterministic_replay_and_log(tmp_path):
    a, b = _episode(seed=9), _episode(seed=9)
    assert a.episode_id == b.episode_id
    assert [canonical_digest(p) for p in a.evidence_packs] == [canonical_digest(p) for p in b.evidence_packs]
    p = tmp_path / "ep.jsonl"
    a.claim_done(require_improvement=False)
    a.export_log(str(p))
    assert verify_log(p)


def test_run_search_rows_have_claim_and_shared_seed():
    rows = run_search([WingState()], steps=5, seed=1, prefer_neuralfoil=False)
    r0, r1 = rows[0], rows[1]
    assert "claim" in r0 and r0["optimizer"]["used"]["evals"] == 5
    assert r0["seeds"] == r1["seeds"]
