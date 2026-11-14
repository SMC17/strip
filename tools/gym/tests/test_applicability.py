"""Advisory measured-polar validity envelope in the aero acceptance gate."""
from __future__ import annotations

from strip_uas_v0.acceptance import accept_aero
from strip_uas_v0.aero_l1 import AeroResult, estimate_aero
from strip_uas_v0.applicability import envelopes
from strip_uas_v0.evidence import build_evidence
from strip_uas_v0.wing import WingState, evaluate_l0


def _aero(re: float, alpha: float = 3.0, fid: str = "L1_neuralfoil_section") -> AeroResult:
    return AeroResult(CL=0.5, CD=0.02, CM=None, LD=25.0, Re_mac=re, alpha_deg=alpha, fidelity=fid,
                      neuralfoil_used=fid == "L1_neuralfoil_section", vspaero_used=False, notes="")


def _adv(acc):
    return {c.name: c.passed for c in acc.checks if c.advisory}


def test_envelope_loaded_from_report():
    env = envelopes()["neuralfoil_small"]
    assert [2.0e5, 5.5e5] in env["validated_Re_bands"]
    assert envelopes()["analytic"]["validated_Re_bands"] == []


def test_inside_envelope_all_advisories_pass():
    acc = accept_aero(_aero(3.0e5), wing=WingState(tc=0.12))
    assert acc.passed and acc.failed_advisories == []
    assert set(_adv(acc)) == {"applicability:Re_in_validated_band", "applicability:alpha_in_validated_range",
                              "applicability:section_tc_in_measured_range"}


def test_outside_envelope_is_advisory_only():
    a = _aero(8.0e4)
    acc = accept_aero(a, wing=WingState(tc=0.07))
    assert acc.passed  # gate and reward unchanged
    assert "applicability:Re_in_validated_band" in acc.failed_advisories
    assert "applicability:section_tc_in_measured_range" in acc.failed_advisories
    assert not any(n.startswith("applicability:") for n in acc.failed_checks)
    d = acc.to_dict()
    assert d["passed"] is True and d["failed_advisories"]


def test_analytic_and_vlm_flagged_unvalidated():
    assert "applicability:Re_in_validated_band" in accept_aero(_aero(3e5, fid="L1_analytic_polar")).failed_advisories
    assert "applicability:section_oracle_validated" in accept_aero(_aero(3e5, fid="L1_vspaero_vlm")).failed_advisories


def test_evidence_records_applicability_claim():
    w = WingState(tc=0.081)  # inside L0 band (>=0.08), below measured symmetric t/c (0.088)
    a = estimate_aero(w, prefer_neuralfoil=True)
    pack = build_evidence(wing=w, l0=evaluate_l0(w), aero=a, seed=0, step=1, episode_id="t", reward=0.0,
                          action=None, monitor_allowed=True, monitor_reasons=[])
    app = pack["applicability"]
    assert app["advisory_only"] is True and app["inside_validated_envelope"] is False
    if pack["acceptance"]["passed"]:
        assert any(c["id"] == "outside_validated_envelope" for c in pack["claims"])
