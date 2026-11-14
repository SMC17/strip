"""Split-conformal utility (mirrored from yard) + Strip applications."""

from __future__ import annotations

import math

import numpy as np
import pytest

from strip_uas_v0.conformal import ASSUMPTIONS, SplitConformal, conformal_quantile, group_cv, random_split_coverage
from strip_uas_v0.conformal_strip import l1_vs_vlm, load_ladson, sample_wings, section_vs_tunnel
from strip_uas_v0.wing import evaluate_l0


def test_quantile_and_too_few_points():
    assert conformal_quantile(np.arange(1.0, 10.0), 0.1) == 9.0
    assert conformal_quantile(np.arange(1.0, 9.0), 0.1) == math.inf


def test_coverage_on_exchangeable_synthetic():
    rng = np.random.default_rng(4)
    p = rng.normal(0, 1, 300)
    y = p + 0.2 * rng.standard_normal(300)
    out = random_split_coverage(p, y, alpha=0.2, score="abs", n_splits=200)
    assert 0.77 <= out["mean_coverage"] <= 0.85


def test_ladson_parse():
    rows = load_ladson()
    assert {r["zone"] for r in rows} == {"80 grit", "120 grit", "180 grit"}
    assert all(r["cd"] > 0 for r in rows)


def test_section_vs_tunnel_records():
    pytest.importorskip("neuralfoil")
    res = section_vs_tunnel()
    for q in ("cd", "cl"):
        rec = res[q]
        assert rec["finite"] and rec["assumptions"] == ASSUMPTIONS
        assert set(rec["leave_one_grit_out"]["per_group"]) == {"80 grit", "120 grit", "180 grit"}
    assert res["cd"]["q_hat"] < 0.25  # NeuralFoil within 25% of tunnel cd at 90% (rel)


def test_l1_vs_vlm_exchangeable_coverage():
    rec = l1_vs_vlm(60, seed=1)
    assert rec["finite"] and rec["test"]["n_test"] == 30
    assert 0.8 <= rec["random_splits"]["mean_coverage"] <= 1.0
    assert all(evaluate_l0(w).feasible for w in sample_wings(10, 1))


def test_group_cv_flags_shift():
    p = np.r_[np.zeros(20), np.zeros(20)]
    y = np.r_[0.01 * np.arange(20), 1.0 + 0.01 * np.arange(20)]
    out = group_cv(p, y, ["a"] * 20 + ["b"] * 20, alpha=0.1, score="abs")
    assert out["per_group"]["a"]["coverage"] == 1.0
    assert SplitConformal(0.1, "abs").fit(p[:20], y[:20]).evaluate(p[20:], y[20:])["coverage"] == 0.0
