"""Simplex-style runtime assurance for Strip-UAS-v0 design search (``rta_simplex_v0``).

Minimal mirror of SMC17/yard ``yard_sea_v0/runtime_assurance.py``: an untrusted
advanced policy proposes a design action, a monitor judges it, and a decision
module substitutes a trusted fallback when the monitor objects; switching back
needs ``recovery_steps`` consecutive safe proposals. Every substitution is
written to the episode evidence as an ``rta_intervention`` record.

Monitor here: the L0 geometric monitor, plus (optional) the wing-alone static
margin band from ``stability.py`` with a CG held from the parent. Fallback: the
largest ``2^-k`` scaling of the proposed action that passes the monitor, else a
no-op. ``FaultyObservation`` injects bias / dropout / freeze into observations
for evaluation.

No formal guarantee, not a certified monitor, no claim of conformance to any
runtime-assurance standard (ASTM F3269 vocabulary only); not FAA / ARP6983.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Callable, Sequence

import numpy as np

from .faults import FaultInjector

LABEL = "rta_simplex_v0"
NO_GUARANTEE = (
    "Simplex-style switching with simple monitors and a scaling fallback. No formal "
    "guarantee, not a certified monitor, no standard-conformance claim."
)


@dataclass
class Verdict:
    safe: bool
    reasons: list[str] = field(default_factory=list)


@dataclass
class Simplex:
    monitor: Callable[[Any, Any], Verdict]
    recovery_steps: int = 1
    in_fallback: bool = False
    _streak: int = 0
    steps: int = 0
    fallback_steps: int = 0
    events: list[dict[str, Any]] = field(default_factory=list)

    def decide(self, t: float, ctx: Any, proposed: Any, fallback_action: Any) -> tuple[Any, Verdict]:
        self.steps += 1
        v = self.monitor(ctx, proposed)
        self._streak = self._streak + 1 if v.safe else 0
        if not self.in_fallback and not v.safe:
            self.in_fallback = True
            self.events.append({"t": t, "switch": "advanced->fallback", "reasons": list(v.reasons)})
        elif self.in_fallback and self._streak >= self.recovery_steps:
            self.in_fallback = False
            self.events.append({"t": t, "switch": "fallback->advanced", "reasons": []})
        if self.in_fallback:
            self.fallback_steps += 1
            return fallback_action, v
        return proposed, v

    def summary(self) -> dict[str, Any]:
        return {"label": LABEL, "steps": self.steps, "fallback_steps": self.fallback_steps,
                "fallback_fraction": self.fallback_steps / self.steps if self.steps else 0.0,
                "n_switches_to_fallback": sum(e["switch"] == "advanced->fallback" for e in self.events),
                "events": list(self.events), "notes": NO_GUARANTEE}


class DesignSimplex:
    """Wrap ``DesignSearchEnv``: replace monitor-rejected actions with a feasible scaled action."""

    def __init__(self, env: Any, *, stability: bool = False, bisections: int = 6,
                 recovery_steps: int = 1) -> None:
        from .monitors import apply_action, monitor_action

        self.env = env
        self.stability = stability
        self.bisections = bisections
        self._apply, self._mon = apply_action, monitor_action
        self._cg = None
        self.simplex = Simplex(self._monitor, recovery_steps=recovery_steps)

    def _monitor(self, wing: Any, action: Sequence[float]) -> Verdict:
        d = self._mon(wing, list(action))
        if not d.allow:
            return Verdict(False, list(d.reason_codes))
        if self.stability:
            from .stability import accept_stability, cg_for_margin, static_margin

            if self._cg is None:
                self._cg = getattr(self.env, "cg", None) or cg_for_margin(self.env.parent,
                                                                          getattr(self.env, "sm_target", 0.10))
            acc = accept_stability(static_margin(self._apply(wing, list(action)), self._cg))
            if not acc.passed:
                return Verdict(False, [f"stability:{n}" for n in acc.failed_checks])
        return Verdict(True)

    def _fallback(self, a: np.ndarray) -> tuple[np.ndarray, float]:
        s = 1.0
        for _ in range(self.bisections):
            s *= 0.5
            if self._monitor(self.env.state, a * s).safe:
                return a * s, s
        return np.zeros_like(a), 0.0

    def reset(self, **kw: Any):
        self._cg = None
        return self.env.reset(**kw)

    def step(self, action: Sequence[float]):
        a = np.asarray(action, dtype=float).reshape(-1)
        fb, scale = (a, 1.0) if self._monitor(self.env.state, a).safe else self._fallback(a)
        out, v = self.simplex.decide(self.env.step_count, self.env.state, a, fb)
        obs, reward, term, trunc, info = self.env.step(out)
        info = dict(info)
        sub = out is not a
        info["rta"] = {"substituted": sub, "reasons": v.reasons, "fallback_scale": scale if sub else None}
        if sub:
            rec = {"type": "rta_intervention", "label": LABEL, "episode_id": self.env.episode_id,
                   "step": self.env.step_count, "proposed_action": a.tolist(),
                   "executed_action": [float(x) for x in out], "fallback_scale": scale,
                   "reasons": v.reasons, "notes": NO_GUARANTEE}
            import json
            import uuid

            body = json.dumps(rec, sort_keys=True, default=str)
            rec["evidence_id"] = f"rta_intervention-{uuid.uuid5(uuid.NAMESPACE_URL, body)}"
            self.env.evidence_packs.append(rec)
            if getattr(self.env, "evidence_dir", None):
                from pathlib import Path

                from .evidence import write_evidence

                write_evidence(rec, Path(self.env.evidence_dir))
        return obs, reward, term, trunc, info

    def summary(self) -> dict[str, Any]:
        return self.simplex.summary() | {"stability_monitor": self.stability}


class FaultyObservation:
    """Eval hook: env observations through a ``FaultInjector`` (channel ``obs``); dropout → stale hold."""

    def __init__(self, env: Any, injector: FaultInjector) -> None:
        self.env, self.injector = env, injector
        self._last: np.ndarray | None = None

    def _f(self, obs: np.ndarray) -> np.ndarray:
        o = self.injector.apply("obs", float(self.env.step_count), obs)
        if o is None:
            o = self._last if self._last is not None else np.asarray(obs, dtype=float)
        self._last = np.asarray(o, dtype=float)
        return self._last.astype(np.float32)

    def reset(self, **kw: Any):
        obs, info = self.env.reset(**kw)
        return self._f(obs), info

    def step(self, action: Any):
        obs, r, te, tr, info = self.env.step(action)
        return self._f(obs), r, te, tr, info
