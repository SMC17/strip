"""Search baselines: random, hill-climb."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np

from . import __version__
from .aero_l1 import estimate_aero
from .env import DesignSearchEnv
from .monitors import monitor_action
from .provenance import OptimizerRecord
from .wing import WingState


@dataclass
class ChildResult:
    wing: WingState
    ld: float
    cd: float
    reward_sum: float
    method: str
    evidence_count: int
    fidelity: str = ""

    def to_dict(self) -> dict[str, Any]:
        return {
            "method": self.method,
            "ld": self.ld,
            "cd": self.cd,
            "reward_sum": self.reward_sum,
            "evidence_count": self.evidence_count,
            "fidelity": self.fidelity,
            "delta_ld_vs_parent": None,
            "wing": self.wing.to_dict(),
        }


def _run_episode(
    env: DesignSearchEnv, policy, steps: int, options: dict[str, Any] | None = None
) -> ChildResult:
    obs, _info = env.reset(options=options)
    total_r = 0.0
    for _ in range(steps):
        action = policy(obs, env)
        obs, reward, term, trunc, _info = env.step(action)
        total_r += float(reward)
        if term or trunc:
            break
    aero = estimate_aero(
        env.state,
        prefer_neuralfoil=env.prefer_neuralfoil,
        prefer_vspaero=env.prefer_vspaero,
    )
    return ChildResult(
        wing=env.state,
        ld=aero.LD,
        cd=aero.CD,
        reward_sum=total_r,
        method=getattr(policy, "name", "policy"),
        evidence_count=len(env.evidence_packs),
        fidelity=aero.fidelity,
    )


def random_policy_factory(rng: np.random.Generator):
    def policy(obs, env):
        return rng.uniform(-1.0, 1.0, size=8).astype(np.float32)

    policy.name = "random"
    return policy


def hillclimb_policy_factory(rng: np.random.Generator):
    best_action = np.zeros(8, dtype=np.float32)

    def policy(obs, env):
        nonlocal best_action
        candidates = [rng.uniform(-1.0, 1.0, size=8) for _ in range(8)]
        candidates.append(best_action)
        best_a = candidates[0]
        best_score = -1e9
        for a in candidates:
            d = monitor_action(env.state, a)
            if not d.allow or d.projected is None:
                score = -1.0
            else:
                # Same acceptance gate as env.step, at the cheap proposal fidelity
                # against a same-fidelity parent baseline (VSPAERO per candidate is
                # too expensive; the accepted step still uses VSPAERO when enabled).
                score, _acc = env.candidate_reward(d.projected)
            if score > best_score:
                best_score = score
                best_a = a
        best_action = np.asarray(best_a, dtype=np.float32)
        return best_action

    policy.name = "hillclimb"
    return policy


def run_search(
    parents: list[WingState],
    steps: int = 40,
    seed: int = 0,
    evidence_root: Path | None = None,
    prefer_neuralfoil: bool = True,
    prefer_vspaero: bool = False,
) -> list[dict[str, Any]]:
    rng = np.random.default_rng(seed)
    results: list[dict[str, Any]] = []
    for i, parent in enumerate(parents):
        parent_aero = estimate_aero(
            parent,
            prefer_neuralfoil=prefer_neuralfoil,
            prefer_vspaero=prefer_vspaero,
        )
        parent_ld = parent_aero.LD
        ed = None if evidence_root is None else evidence_root / f"parent_{i:02d}"
        env = DesignSearchEnv(
            parent=parent,
            max_steps=steps,
            seed=seed + i,
            evidence_dir=str(ed) if ed else None,
            prefer_neuralfoil=prefer_neuralfoil,
            prefer_vspaero=prefer_vspaero,
        )
        for factory in (random_policy_factory, hillclimb_policy_factory):
            policy = factory(rng)
            name = getattr(policy, "name", "policy")
            opt = OptimizerRecord(
                implementation=f"strip_uas_v0.search.{name}",
                version=__version__,
                settings={"candidates_per_step": 8} if name == "hillclimb" else {"dist": "uniform[-1,1]^8"},
                max_evals=int(steps),
            ).start()
            # Same episode_index for every policy => shared env randomness (CRN).
            child = _run_episode(env, policy, steps, options={"episode_index": 0, "optimizer": opt})
            row = child.to_dict()
            row["optimizer"] = opt.to_dict()
            row["seeds"] = dict(env.seeds)
            row["episode_id"] = env.episode_id
            row["delta_ld_vs_parent"] = child.ld - parent_ld
            row["parent_ld"] = parent_ld
            row["parent_fidelity"] = parent_aero.fidelity
            row["parent_index"] = i
            # Measure-then-claim: "improved" is the env's fresh re-measurement verdict.
            verdict = env.claim_done({"LD": child.ld})
            row["improved"] = bool(verdict["accepted"])
            row["claim"] = {"accepted": verdict["accepted"], "reasons": verdict["reasons"]}
            row["prefer_vspaero"] = prefer_vspaero
            results.append(row)
    return results
