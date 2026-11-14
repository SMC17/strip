"""No-NeuralFoil fallback: published-basis section C_d0 and Nita & Scholz Oswald factor."""
from __future__ import annotations

import json
from pathlib import Path

import pytest

from strip_uas_v0 import aero_l1
from strip_uas_v0.analytic_fallback import lifting_line_e
from strip_uas_v0.wing import WingState

REP = Path(__file__).resolve().parents[1] / "reports" / "validation" / "analytic_fallback.json"


def test_oswald_matches_lifting_line_unswept():
    for ar in (6.0, 10.0, 16.0):
        for lam in (0.35, 0.6, 1.0):
            assert aero_l1.oswald_nita_scholz(ar, lam, 0.0) == pytest.approx(lifting_line_e(ar, lam), abs=0.015)


def test_lifting_line_elliptic_limit_and_rectangular_reference():
    # Rectangular AR 6: classic delta ~0.05 (Anderson Fig. 5.20 / Glauert) -> e ~0.95
    assert lifting_line_e(6.0, 1.0) == pytest.approx(0.95, abs=0.01)


def test_oswald_optimum_taper_moves_with_sweep():
    e0 = [aero_l1.oswald_nita_scholz(8, lam / 100, 0.0) for lam in range(20, 101)]
    e30 = [aero_l1.oswald_nita_scholz(8, lam / 100, 30.0) for lam in range(20, 101)]
    lam0 = (20 + e0.index(max(e0))) / 100
    lam30 = (20 + e30.index(max(e30))) / 100
    assert lam0 == pytest.approx(0.45, abs=0.02) and lam30 < lam0  # NASA optimum 0.45 exp(-0.0375 phi)


def test_section_cd0_buildup_published_values():
    # Raymer eq 12.27 at Re 1e6: C_f = 0.455/6^2.58
    assert aero_l1.skin_friction_turbulent(1e6) == pytest.approx(0.455 / 6**2.58)
    assert aero_l1.section_cd0_buildup(0.12, 6e6) == pytest.approx(0.0082, abs=3e-4)  # Ladson C_d at C_l=0 ~0.0081
    assert aero_l1.section_cd0_buildup(0.18, 4e5) > aero_l1.section_cd0_buildup(0.10, 4e5)


def test_fallback_wing_uses_published_e():
    w = WingState()
    a = aero_l1.estimate_aero(w, prefer_neuralfoil=False)
    e = aero_l1.oswald_nita_scholz(w.aspect_ratio(), w.taper, w.sweep_deg)
    cd_sec = aero_l1.section_cd0_buildup(w.tc, a.Re_mac)
    assert a.CD == pytest.approx(cd_sec + a.CL**2 / (3.141592653589793 * w.aspect_ratio() * e), rel=1e-9)


def test_report_shows_improvement():
    r = json.loads(REP.read_text())
    lad = r["section_ladson_naca0012"]
    assert lad["after"]["median_abs_E_CD_pct"] < lad["before"]["median_abs_E_CD_pct"] / 5
    assert r["oswald"]["mean_abs_err_nita_scholz"] < 0.01 < r["oswald"]["mean_abs_err_old"]


@pytest.mark.parametrize("w", [WingState(), WingState(span_m=3.2, chord_root_m=0.22, taper=0.45, sweep_deg=18.0, tc=0.10)])
def test_both_section_paths_use_the_same_published_e(w):
    from strip_uas_v0.teachers import neuralfoil_stub

    e = aero_l1.oswald_nita_scholz(w.aspect_ratio(), w.taper, w.sweep_deg)
    assert aero_l1.span_efficiency(w) == pytest.approx(e)
    a_fb = aero_l1.estimate_aero(w, prefer_neuralfoil=False)
    cd_sec = aero_l1.section_cd0_buildup(w.tc, a_fb.Re_mac)
    assert (a_fb.CD - cd_sec) * 3.141592653589793 * w.aspect_ratio() * e == pytest.approx(a_fb.CL**2, rel=1e-9)
    if not neuralfoil_stub.detect().available:
        pytest.skip("neuralfoil not installed")
    a_nf = aero_l1.estimate_aero(w)
    assert a_nf.neuralfoil_used
    kp = neuralfoil_stub.naca4_kulfan(w.tc, w.camber)
    r = neuralfoil_stub.run(alpha_deg=w.alpha_deg + 0.5 * w.twist_deg, Re=a_nf.Re_mac, model_size="small",
                            kulfan_parameters=kp, airfoil="x")
    cd_sec_nf = max(float(r["CD"]), 1e-5)
    # induced part of the NeuralFoil-path C_D uses the same e as the fallback
    assert (a_nf.CD - cd_sec_nf) * 3.141592653589793 * w.aspect_ratio() * e == pytest.approx(a_nf.CL**2, rel=1e-6)
