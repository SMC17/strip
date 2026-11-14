import numpy as np

from strip_uas_v0.env import DesignSearchEnv
from strip_uas_v0.wing import WingState


def test_reset_and_step():
    env = DesignSearchEnv(parent=WingState(), max_steps=5, seed=1, prefer_neuralfoil=False)
    obs, info = env.reset()
    assert obs.shape == (13,)
    obs2, reward, term, trunc, info2 = env.step(np.zeros(8))
    assert obs2.shape == (13,)
    assert isinstance(reward, float)
    assert info2["rejected"] is False
    assert "LD" in info2


def test_illegal_action_path_stays_finite():
    env = DesignSearchEnv(parent=WingState(), max_steps=5, seed=2, prefer_neuralfoil=False)
    env.reset()
    a = np.zeros(7)
    a[2] = -1.0  # taper down hard
    for _ in range(40):
        _, reward, _, _, info = env.step(a)
        if info.get("rejected"):
            assert reward < 0
            break
    assert np.isfinite(env.state.span_m)
