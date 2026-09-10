"""DesignSearchEnv — Gymnasium-compatible long-horizon wing/UAS design search."""

from __future__ import annotations

import uuid
from typing import Any

import numpy as np

from .aero_l1 import AeroResult, estimate_aero
from .evidence import build_evidence, write_evidence
from .monitors import apply_action, monitor_action
from .wing import WingState, evaluate_l0

try:
    import gymnasium as gym
    from gymnasium import spaces

    _HAS_GYM = True
except ImportError:  # pragma: no cover
    gym = None  # type: ignore
    spaces = None  # type: ignore
    _HAS_GYM = False


def _reward(
    w: WingState,
    parent_ld: float,
    parent_area: float,
    *,
    prefer_neuralfoil: bool = True,
    prefer_vspaero: bool = False,
    parent_cd: float | None = None,
) -> float:
    """Improve L/D (and optionally CL/CD) vs parent; preserve area.

    When ``prefer_vspaero`` is set, ``estimate_aero`` pulls VSPAERO CL/CD if
    OpenVSP is present; otherwise NeuralFoil/analytic remains the cheap L1.
    """
    a = estimate_aero(
        w, prefer_neuralfoil=prefer_neuralfoil, prefer_vspaero=prefer_vspaero
    )
    # Improve L/D vs parent; preserve area (payload/mission proxy)
    ld_term = (a.LD - parent_ld) / max(abs(parent_ld), 1e-6)
    area_term = (w.area_m2() - parent_area) / max(parent_area, 1e-6)
    # Mild preference for modest CL (usable lift) without chasing stall
    cl_term = min(0.3, max(0.0, a.CL - 0.15)) * 0.2
    # Optional CD improvement vs parent (helps when L/D noisy)
    cd_term = 0.0
    if parent_cd is not None and parent_cd > 0:
        cd_term = (parent_cd - a.CD) / max(parent_cd, 1e-6) * 0.5
    return float(2.0 * ld_term + 0.3 * area_term + cl_term + cd_term)


class DesignSearchEnv(gym.Env if _HAS_GYM else object):  # type: ignore[misc]
    """Multi-step parametric wing morph under L0 monitors + L1 aero reward.

    Reward uses NeuralFoil/analytic by default (cheap L1). Set
    ``prefer_vspaero=True`` to drive reward from VSPAERO CL/CD when
    ``vspscript``+``vspaero`` are available; skips cleanly otherwise.
    """

    metadata = {"render_modes": []}

    def __init__(
        self,
        parent: WingState | None = None,
        max_steps: int = 50,
        seed: int = 0,
        evidence_dir: str | None = None,
        prefer_neuralfoil: bool = True,
        prefer_vspaero: bool = False,
    ) -> None:
        self.max_steps = max_steps
        self._seed = seed
        self.evidence_dir = evidence_dir
        self.prefer_neuralfoil = prefer_neuralfoil
        self.prefer_vspaero = prefer_vspaero
        self.parent = parent or WingState()
        self.episode_id = ""
        self.state = self.parent
        self.step_count = 0
        parent_aero = self._estimate(self.parent)
        self.parent_ld = parent_aero.LD
        self.parent_cd = parent_aero.CD
        self.parent_aero_fidelity = parent_aero.fidelity
        self.parent_area = self.parent.area_m2()
        self.evidence_packs: list[dict[str, Any]] = []
        self.np_random = np.random.default_rng(seed)
        if _HAS_GYM:
            self.action_space = spaces.Box(low=-1.0, high=1.0, shape=(7,), dtype=np.float32)
            # obs: wing vector (7) + [CL, CD, LD, area_norm, step_frac]
            self.observation_space = spaces.Box(
                low=-np.inf, high=np.inf, shape=(12,), dtype=np.float32
            )

    def _estimate(self, w: WingState) -> AeroResult:
        return estimate_aero(
            w,
            prefer_neuralfoil=self.prefer_neuralfoil,
            prefer_vspaero=self.prefer_vspaero,
        )

    def _obs(self) -> np.ndarray:
        a = self._estimate(self.state)
        vec = self.state.as_vector() + [
            a.CL,
            a.CD,
            a.LD,
            self.state.area_m2() / max(self.parent_area, 1e-6),
            self.step_count / max(self.max_steps, 1),
        ]
        return np.asarray(vec, dtype=np.float32)

    def reset(self, *, seed: int | None = None, options: dict | None = None):
        if seed is not None:
            self._seed = seed
            self.np_random = np.random.default_rng(seed)
        if options and "parent" in options:
            self.parent = options["parent"]
        self.episode_id = str(uuid.uuid4())
        keys = (
            "span_m",
            "chord_root_m",
            "taper",
            "sweep_deg",
            "tc",
            "twist_deg",
            "alpha_deg",
        )
        self.state = WingState(**{k: getattr(self.parent, k) for k in keys})
        self.step_count = 0
        parent_aero = self._estimate(self.parent)
        self.parent_ld = parent_aero.LD
        self.parent_cd = parent_aero.CD
        self.parent_aero_fidelity = parent_aero.fidelity
        self.parent_area = self.parent.area_m2()
        self.evidence_packs = []
        obs = self._obs()
        info = {
            "episode_id": self.episode_id,
            "parent_ld": self.parent_ld,
            "parent_cd": self.parent_cd,
            "parent_aero_fidelity": self.parent_aero_fidelity,
            "prefer_vspaero": self.prefer_vspaero,
        }
        return obs, info

    def step(self, action):
        action = list(np.asarray(action, dtype=float).reshape(-1))
        decision = monitor_action(self.state, action)
        self.step_count += 1
        terminated = False
        truncated = self.step_count >= self.max_steps

        if not decision.allow or decision.projected is None:
            reward = -1.0
            l0 = evaluate_l0(decision.projected or apply_action(self.state, action))
            pack = build_evidence(
                wing=decision.projected or self.state,
                l0=l0,
                aero=None,
                seed=self._seed,
                step=self.step_count,
                episode_id=self.episode_id,
                reward=reward,
                action=action,
                monitor_allowed=False,
                monitor_reasons=decision.reason_codes,
                parent_id=None,
            )
            self.evidence_packs.append(pack)
            if self.evidence_dir:
                from pathlib import Path

                write_evidence(pack, Path(self.evidence_dir))
            info = {"monitor": decision.to_dict(), "rejected": True}
            return self._obs(), reward, terminated, truncated, info

        self.state = decision.projected
        l0 = evaluate_l0(self.state)
        aero = self._estimate(self.state)
        reward = _reward(
            self.state,
            self.parent_ld,
            self.parent_area,
            prefer_neuralfoil=self.prefer_neuralfoil,
            prefer_vspaero=self.prefer_vspaero,
            parent_cd=self.parent_cd,
        )
        pack = build_evidence(
            wing=self.state,
            l0=l0,
            aero=aero,
            seed=self._seed,
            step=self.step_count,
            episode_id=self.episode_id,
            reward=reward,
            action=action,
            monitor_allowed=True,
            monitor_reasons=[],
        )
        self.evidence_packs.append(pack)
        if self.evidence_dir:
            from pathlib import Path

            write_evidence(pack, Path(self.evidence_dir))
        info = {
            "CL": aero.CL,
            "CD": aero.CD,
            "LD": aero.LD,
            "fidelity": aero.fidelity,
            "neuralfoil_used": aero.neuralfoil_used,
            "vspaero_used": aero.vspaero_used,
            "monitor": decision.to_dict(),
            "rejected": False,
        }
        return self._obs(), reward, terminated, truncated, info
