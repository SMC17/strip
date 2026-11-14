"""Runtime monitors — reject illegal actions before L1 aero evaluation."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from .wing import WingState, evaluate_l0


@dataclass
class MonitorDecision:
    allow: bool
    reason_codes: list[str]
    projected: WingState | None

    def to_dict(self) -> dict[str, Any]:
        return {
            "allow": self.allow,
            "reason_codes": list(self.reason_codes),
            "projected": None if self.projected is None else self.projected.to_dict(),
        }


def apply_action(w: WingState, action: list[float] | tuple[float, ...]) -> WingState:
    """Action: bounded relative/absolute deltas for 8 wing params.

    Indices: [span, chord_root, taper, sweep, tc, twist, alpha, camber]. A 7-element action
    (pre-camber agents) leaves camber unchanged.
    """
    scales = [0.05, 0.05, 0.03, 1.5, 0.01, 0.5, 0.5, 0.005]
    vals = w.as_vector()
    out = []
    for i, a in enumerate(action[:8]):
        a = max(-1.0, min(1.0, float(a)))
        if i in (0, 1):  # span, chord — relative
            out.append(vals[i] * (1.0 + a * scales[i]))
        else:  # taper, sweep, tc, twist, alpha — additive
            out.append(vals[i] + a * scales[i])
    out += vals[len(out):]
    return WingState.from_vector(out).clamp_soft()


def monitor_action(
    w: WingState, action: list[float] | tuple[float, ...]
) -> MonitorDecision:
    projected = apply_action(w, action)
    report = evaluate_l0(projected)
    if not report.feasible:
        return MonitorDecision(
            allow=False,
            reason_codes=report.violations,
            projected=projected,
        )
    return MonitorDecision(allow=True, reason_codes=[], projected=projected)
