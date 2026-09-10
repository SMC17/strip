"""Tests for Strip UAS aero oracle stubs (incl. VSPAERO)."""

from __future__ import annotations

import pytest

from strip_uas_v0.teachers import jsbsim_stub, neuralfoil_stub, openvsp_stub, vspaero_l1


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


def test_vspaero_detect_and_skip():
    avail = vspaero_l1.detect()
    d = avail.to_dict()
    assert "available" in d
    assert "install_hint" in d
    fake = vspaero_l1.VSPAEROAvailability()
    r = vspaero_l1.run(availability=fake)
    assert r["skipped"] is True
    assert r["skip_reason"] == "vspaero_unavailable"
    assert r["fidelity"] == vspaero_l1.FIDELITY_PENDING
    assert r["CL"] is None


def test_vspaero_parse_markers():
    text = "strip_uas_CL=0.182078\nstrip_uas_CD=0.00629931\nstrip_uas_CM=-0.0411911\n"
    m = vspaero_l1.parse_markers(text)
    assert m["CL"] == pytest.approx(0.182078)
    assert m["CD"] == pytest.approx(0.00629931)
    assert m["CM"] == pytest.approx(-0.0411911)


def test_vspaero_parse_polar(tmp_path):
    polar = tmp_path / "strip_uas_vspaero.polar"
    polar.write_text(
        "\n".join(
            [
                "header junk",
                "      Beta             Mach             AoA             Re/1e6             CLo             CLi            CLtot              CDo              CDi             CDtot              CSo              CSi            CStot               L/D              E               CMox             CMoy             CMoz             CMix             CMiy             CMiz             CMxtot           CMytot           CMztot",
                "  0.000000000000   0.100000000000   2.000000000000  10.000000000000  -0.000188046132   0.182265973011   0.182077926879   0.005384936665   0.000914368647   0.006299305313   0.0 0.0 0.0 28.9 0.96 0.0 0.0 0.0 0.0 -0.041191086938 0.0 0.0 -0.041191086938 0.0",
            ]
        ),
        encoding="utf-8",
    )
    m = vspaero_l1.parse_polar(polar)
    assert m["CL"] == pytest.approx(0.182077926879)
    assert m["CD"] == pytest.approx(0.006299305313)
    assert m["CM"] == pytest.approx(-0.041191086938)


def test_vspaero_thin_wing_when_available(tmp_path):
    avail = vspaero_l1.detect()
    if not avail.available:
        pytest.skip("vspscript/vspaero not installed under vendor/openvsp")
    r = vspaero_l1.run(
        availability=avail,
        work_dir=str(tmp_path),
        alpha_deg=2.0,
        span_m=2.4,
        chord_root_m=0.30,
        taper=0.70,
        sweep_deg=5.0,
    )
    assert r["skipped"] is False
    assert r["fidelity"] == vspaero_l1.FIDELITY
    assert r["CL"] is not None and abs(r["CL"]) > 0.05
    assert r["CD"] is not None and 0 < r["CD"] < 0.2
    assert r["CM"] is not None
    assert r["LD"] is not None and r["LD"] > 1.0
    assert (tmp_path / "strip_uas_vspaero.vsp3").is_file()
    assert (tmp_path / "strip_uas_vspaero.polar").is_file()


def test_teacher_protocol_exports():
    from strip_uas_v0 import teachers

    assert hasattr(teachers, "vspaero_l1")
    assert "Teacher protocol" in (teachers.__doc__ or "")
