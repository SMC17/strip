"""DesignSearchEnv — Gymnasium-compatible long-horizon wing/UAS design search."""

from __future__ import annotations

from typing import Any

import numpy as np

from .acceptance import accept_aero
from .aero_l1 import AeroResult, estimate_aero
from .evidence import build_evidence, write_evidence
from .monitors import apply_action, monitor_action
from .provenance import (
    OptimizerRecord,
    deterministic_episode_id,
    export_episode_log,
    seeds_record,
)
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
    aero: Any = None,
) -> float:
    """Improve L/D (and optionally CL/CD) vs parent; preserve area.

    When ``prefer_vspaero`` is set, ``estimate_aero`` pulls VSPAERO CL/CD if
    OpenVSP is present; otherwise NeuralFoil/analytic remains the cheap L1.
    """
    a = aero if aero is not None else estimate_aero(
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
        optimizer: OptimizerRecord | None = None,
        stability_gate: bool = False,
        cg: Any = None,
        sm_target: float = 0.10,
    ) -> None:
        # Static-stability gate (wing-alone VLM neutral point; CG is a convention). With
        # ``cg=None`` the CG is fixed where the parent has ``sm_target`` margin and held.
        self.stability_gate = stability_gate
        self._cg_given = cg
        self.sm_target = sm_target
        self.cg = cg
        self.max_steps = max_steps
        self._seed = seed
        self.base_seed = int(seed)
        self.episode_index = -1
        self.seeds: dict[str, Any] = seeds_record(self.base_seed, 0)
        self.optimizer = optimizer or OptimizerRecord(implementation="unspecified")
        self.last_claim: dict[str, Any] | None = None
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

    def _gate(self, w: WingState, acc: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any] | None]:
        """Fold the static-margin checks into ``acc`` when the stability gate is on."""
        if not self.stability_gate:
            return acc, None
        from .stability import accept_stability, cg_for_margin, merge_acceptance, static_margin

        if self.cg is None:
            self.cg = cg_for_margin(self.parent, self.sm_target)
        stab = static_margin(w, self.cg)
        return merge_acceptance(acc, accept_stability(stab)), stab

    def _cheap_parent(self) -> AeroResult:
        """Parent aero at the cheap proposal fidelity (never VSPAERO), cached per parent."""
        key = tuple(self.parent.as_vector())
        cached = getattr(self, "_cheap_parent_cache", None)
        if cached is None or cached[0] != key:
            cached = (key, estimate_aero(self.parent, prefer_neuralfoil=self.prefer_neuralfoil, prefer_vspaero=False))
            self._cheap_parent_cache = cached
        return cached[1]

    def candidate_reward(self, w: WingState) -> tuple[float, dict[str, Any]]:
        """Score an already-monitored proposal for look-ahead search.

        Uses the cheap fidelity (NeuralFoil / analytic; VSPAERO per candidate is
        too expensive) and the *same-fidelity* parent baseline, then applies the
        acceptance gate exactly as ``step`` does: out-of-envelope or
        mixed-fidelity proposals score -1 instead of looking attractive.
        Returns ``(score, acceptance_dict)``.
        """
        cp = self._cheap_parent()
        a = estimate_aero(w, prefer_neuralfoil=self.prefer_neuralfoil, prefer_vspaero=False)
        acc, _ = self._gate(w, accept_aero(a, parent_fidelity=cp.fidelity).to_dict())
        if not acc["passed"]:
            return -1.0, acc
        score = _reward(
            w,
            cp.LD,
            self.parent_area,
            prefer_neuralfoil=self.prefer_neuralfoil,
            prefer_vspaero=False,
            parent_cd=cp.CD,
            aero=a,
        )
        return score, acc

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
        # Seeded resets with shared randomness: RNG derived from (base_seed, episode_index).
        if seed is not None:
            self.base_seed = int(seed)
            self.episode_index = -1
        options = options or {}
        if "parent" in options:
            self.parent = options["parent"]
        if "optimizer" in options:
            self.optimizer = options["optimizer"]
        if "parent" in options and self._cg_given is None:
            self.cg = None  # re-derive the fixed CG from the new parent
        self.episode_index = int(options.get("episode_index", self.episode_index + 1))
        self.seeds = seeds_record(self.base_seed, self.episode_index)
        self._seed = self.seeds["episode_seed"]
        self.np_random = np.random.default_rng(self._seed)
        self.last_claim = None
        self.episode_id = deterministic_episode_id(
            self.base_seed, self.episode_index, self.parent.as_vector()
        )
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
            "seeds": dict(self.seeds),
        }
        return obs, info

    def step(self, action):
        action = list(np.asarray(action, dtype=float).reshape(-1))
        self.optimizer.tick()
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
                optimizer=self.optimizer.to_dict(),
                seeds=dict(self.seeds),
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
        acc, stab = self._gate(
            self.state, accept_aero(aero, parent_fidelity=self.parent_aero_fidelity).to_dict()
        )
        if acc["passed"]:
            reward = _reward(
                self.state,
                self.parent_ld,
                self.parent_area,
                prefer_neuralfoil=self.prefer_neuralfoil,
                prefer_vspaero=self.prefer_vspaero,
                parent_cd=self.parent_cd,
            )
        else:
            # Acceptance gate: out-of-envelope or mixed-fidelity numbers earn no credit.
            reward = -1.0
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
            acceptance=acc,
            optimizer=self.optimizer.to_dict(),
            seeds=dict(self.seeds),
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
            "acceptance": acc,
        }
        if stab is not None:
            info["stability"] = stab
        return self._obs(), reward, terminated, truncated, info

    def claim_done(
        self,
        claimed: dict[str, float] | None = None,
        *,
        rel_tol: float = 1e-6,
        require_improvement: bool = True,
    ) -> dict[str, Any]:
        """Measure-then-claim: accept "done" only after re-measuring the final wing.

        Rebuilds the wing from its parameter vector, re-runs L0 and the aero oracle,
        applies the acceptance gate (incl. same fidelity as the parent), and checks
        any claimed ``LD``/``CL``/``CD``/``area`` against the fresh measurement.
        """
        fresh = WingState.from_vector(self.state.as_vector())
        l0 = evaluate_l0(fresh)
        aero = self._estimate(fresh)
        acc_d, stab = self._gate(fresh, accept_aero(aero, parent_fidelity=self.parent_aero_fidelity).to_dict())
        measured = {"LD": aero.LD, "CL": aero.CL, "CD": aero.CD, "area": fresh.area_m2()}
        if stab is not None:
            measured["static_margin"] = stab["static_margin"]
        reasons: list[str] = []
        if not l0.feasible:
            reasons.append("l0_infeasible:" + ",".join(l0.violations))
        if not acc_d["passed"]:
            reasons.append("acceptance_failed:" + ",".join(acc_d["failed_checks"]))
        mismatches = {}
        for k, v in (claimed or {}).items():
            if k not in measured:
                reasons.append(f"unmeasurable_claim:{k}")
                continue
            m = measured[k]
            if abs(float(v) - m) > rel_tol * max(abs(m), 1e-12):
                mismatches[k] = {"claimed": float(v), "measured": m}
        if mismatches:
            reasons.append("claim_mismatch:" + ",".join(sorted(mismatches)))
        improved = aero.LD > self.parent_ld
        if require_improvement and not improved:
            reasons.append("no_improvement_vs_parent")
        verdict = {
            "type": "claim",
            "schema": "strip_uas_v0.claim.v1",
            "episode_id": self.episode_id,
            "step": self.step_count,
            "accepted": not reasons,
            "reasons": reasons,
            "measured": measured,
            "claimed": dict(claimed or {}),
            "mismatches": mismatches,
            "parent_ld": self.parent_ld,
            "parent_fidelity": self.parent_aero_fidelity,
            "improved": improved,
            "l0": l0.to_dict(),
            "acceptance": acc_d,
            "stability": stab,
            "wing": fresh.to_dict(),
            "optimizer": self.optimizer.to_dict(),
            "seeds": dict(self.seeds),
            "notes": "Measure-then-claim verdict from fresh re-evaluation; not FAA / ARP6983.",
        }
        self.evidence_packs.append(verdict)
        self.last_claim = verdict
        return verdict

    def export_log(self, path: str) -> dict[str, Any]:
        """Digest-chained JSONL log of this episode's evidence + claim records."""
        return export_episode_log(
            self.evidence_packs,
            path,
            header={
                "episode_id": self.episode_id,
                "seeds": dict(self.seeds),
                "optimizer": self.optimizer.to_dict(),
                "parent": self.parent.to_dict(),
                "max_steps": self.max_steps,
            },
        )
