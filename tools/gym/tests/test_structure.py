"""Spar-depth floor (structure.py) and its L0 hook."""
from __future__ import annotations

import dataclasses
import json
import math
from pathlib import Path

import pytest

from strip_uas_v0 import structure as st
from strip_uas_v0.wing import WingState, evaluate_l0

REP = Path(__file__).resolve().parents[1] / "reports" / "validation" / "section_tc_impact.json"


def test_published_constants():
    assert st.N_LIMIT * st.FACTOR_OF_SAFETY == pytest.approx(5.7)
    assert st.MATERIALS["sitka_spruce"] == pytest.approx(38.7e6)


def test_root_moment_elliptic():
    w = WingState(span_m=2.0)
    m = st.root_bending_moment(w, mass_kg=1.0)
    assert m == pytest.approx(5.7 * st.G / 2 * 4 / (3 * math.pi) * 1.0)


def test_floor_scales_with_span_and_chord():
    base = st.spar_check(WingState()).tc_required
    assert st.spar_check(WingState(span_m=3.4)).tc_required > base
    assert st.spar_check(WingState(chord_root_m=0.4)).tc_required < base
    # h_req ∝ sqrt(M / c) and t/c_req = h_req / c  ->  ∝ sqrt(b) / c^1.5
    w1, w2 = WingState(span_m=2.0, chord_root_m=0.3), WingState(span_m=4.0, chord_root_m=0.3)
    assert st.spar_check(w2).tc_required / st.spar_check(w1).tc_required == pytest.approx(math.sqrt(2))


def test_l0_rejects_thin_high_ar_wing_and_accepts_default():
    assert evaluate_l0(WingState()).feasible
    thin = WingState(span_m=3.4, chord_root_m=0.2, tc=0.10)
    rep = evaluate_l0(thin)
    assert not rep.feasible and any(v.startswith("tc_below_spar_depth_floor") for v in rep.violations)
    assert rep.metrics["tc_required_spar"] == pytest.approx(st.spar_check(thin).tc_required)


def test_ranking_study_records_floor():
    sf = json.loads(REP.read_text())["structural_floor"]
    assert sf["optimal_tc_with_floor"]["share_at_lower_bound"] < sf["optimal_tc_free"]["share_at_lower_bound"]
    assert sf["optimal_tc_with_floor"]["median"] >= sf["optimal_tc_free"]["median"]
