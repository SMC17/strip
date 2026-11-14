"""Starting wings must have positive lift / L/D so improvement is not inflated."""

from __future__ import annotations

import pytest

from strip_uas_v0.aero_l1 import estimate_aero
from strip_uas_v0.gallery import MIN_PARENT_CL, default_parents, screen_parent
from strip_uas_v0.wing import WingState


def test_negative_lift_wing_rejected():
    w = WingState(twist_deg=-4.0, alpha_deg=-3.0)
    chk = screen_parent(w, prefer_neuralfoil=False)
    assert chk["ok"] is False
    assert any(r.startswith("CL<=") or r == "LD<=0" or r.startswith("acceptance") for r in chk["reasons"])


@pytest.mark.parametrize("seed", [0, 1, 2, 3, 7])
def test_default_parents_all_positive_lift(seed):
    stats: dict = {}
    parents = default_parents(8, seed=seed, prefer_neuralfoil=False, stats=stats)
    assert len(parents) == 8
    for p in parents:
        a = estimate_aero(p, prefer_neuralfoil=False, prefer_vspaero=False)
        assert a.CL > MIN_PARENT_CL and a.LD > 0
    assert stats["max_tries"] >= 1 and "n_rejected" in stats


def test_bounded_retries_raise(monkeypatch):
    import strip_uas_v0.gallery as g

    monkeypatch.setattr(g, "screen_parent", lambda w, **kw: {"ok": w == WingState(), "reasons": ["x"], "CL": 0, "LD": 0})
    with pytest.raises(ValueError, match="could not draw"):
        g.default_parents(3, seed=0, max_tries=4)
