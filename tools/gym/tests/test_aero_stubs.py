"""Tests for Strip UAS aero oracle stubs."""

from __future__ import annotations

import pytest

from strip_uas_v0.teachers import jsbsim_stub, neuralfoil_stub, openvsp_stub


def test_openvsp_detect_and_skip():
    avail = openvsp_stub.detect()
    d = avail.to_dict()
    assert "available" in d
    fake = openvsp_stub.OpenVSPAvailability()
    r = openvsp_stub.run(availability=fake)
    assert r["skipped"] is True
    assert r["skip_reason"] == "openvsp_unavailable"


def test_neuralfoil_skip_when_unavailable():
    fake = neuralfoil_stub.NeuralFoilAvailability()
    r = neuralfoil_stub.run(availability=fake)
    assert r["skipped"] is True


def test_jsbsim_skip_when_unavailable():
    fake = jsbsim_stub.JSBSimAvailability()
    r = jsbsim_stub.run(availability=fake)
    assert r["skipped"] is True


def test_neuralfoil_thin_call_if_installed():
    avail = neuralfoil_stub.detect()
    if not avail.available:
        pytest.skip("neuralfoil not installed")
    r = neuralfoil_stub.run(alpha_deg=2.0, Re=1e6, model_size="small")
    assert r["skipped"] is False
    assert r["CL"] is not None
