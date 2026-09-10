from strip_uas_v0.env import DesignSearchEnv
from strip_uas_v0.wing import WingState


def test_evidence_emitted():
    env = DesignSearchEnv(parent=WingState(), max_steps=3, seed=0, prefer_neuralfoil=False)
    env.reset()
    env.step([0.1, 0, 0, 0, 0, 0, 0])
    assert len(env.evidence_packs) >= 1
    pack = env.evidence_packs[0]
    assert pack["schema"] == "strip_uas_v0.evidence.v1"
    assert "odd" in pack and "claims" in pack and "gsn_stub" in pack
    assert pack["agent_class"] == "learned_offline"
    assert pack["odd"]["limits"]["not_faa_certification"] is True
    assert pack["odd"]["limits"]["not_arp6983_conformance"] is True
    sa = pack["strip_assurance"]
    assert sa["not_certification"] is True
    assert sa["not_faa_ai_assurance_approval"] is True
    assert sa["not_arp6983_conformance"] is True
