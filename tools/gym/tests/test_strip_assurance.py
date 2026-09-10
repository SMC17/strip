from strip_uas_v0.env import DesignSearchEnv
from strip_uas_v0.strip_assurance import strip_overlay


def test_strip_overlay_on_env_step():
    env = DesignSearchEnv(max_steps=3, seed=0, evidence_dir=None, prefer_neuralfoil=False)
    env.reset()
    env.step([0.0] * 7)
    packs = env.evidence_packs
    assert packs
    sa = packs[-1]["strip_assurance"]
    assert sa["not_certification"] is True
    assert sa["product_line"] == "strip_uas"
    assert sa["assurance_level"] in ("L0_reject", "L1_rank")
    assert "validation_gates" in sa


def test_overlay_reject():
    sa = strip_overlay(
        {"monitor": {"allow": False}, "l0": {"feasible": False}, "claims": [], "aero": None}
    )
    assert sa["assurance_level"] == "L0_reject"
