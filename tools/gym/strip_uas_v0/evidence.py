"""Evidence / assurance pack emission for every evaluation."""

from __future__ import annotations

import json
import platform
import time
import uuid
from pathlib import Path
from typing import Any

from . import __version__
from .aero_l1 import AeroResult
from .strip_assurance import strip_overlay
from .wing import L0Report, WingState


def build_evidence(
    *,
    wing: WingState,
    l0: L0Report,
    aero: AeroResult | None,
    seed: int,
    step: int,
    episode_id: str,
    reward: float,
    action: list[float] | None,
    monitor_allowed: bool,
    monitor_reasons: list[str],
    parent_id: str | None = None,
) -> dict[str, Any]:
    odd = {
        "domain": "exploratory_parametric_wing_uas",
        "alpha_deg": wing.alpha_deg,
        "span_m": wing.span_m,
        "fluid": "isa_sl_air_1p225",
        "geometry_family": "trapezoidal_wing",
        "limits": {
            "not_faa_certification": True,
            "not_arp6983_conformance": True,
            "not_flight_clearance": True,
            "not_vspaero_panel": True,  # VLM reward path is still not a cert panel case
            "vspaero_reward_exploratory_only": True,
            "learning_in_ops": False,
        },
    }
    claims: list[dict[str, Any]] = []
    if l0.feasible and aero is not None:
        claims.append(
            {
                "id": "aero_rank_l1",
                "statement": (
                    "Wing is L0-feasible and ranked by L1 section+induced aero "
                    f"(fidelity={aero.fidelity}); NOT a flight-test or cert claim."
                ),
                "status": "supported_at_l1",
                "evidence": ["l0_report", "aero_l1"],
            }
        )
        claims.append(
            {
                "id": "geometry_envelope",
                "statement": (
                    f"AR={wing.aspect_ratio():.2f}, taper={wing.taper:.2f}, "
                    f"sweep={wing.sweep_deg:.1f} deg within exploratory L0 bands."
                ),
                "status": "supported_at_l0",
                "evidence": ["l0_report"],
            }
        )
        if aero.neuralfoil_used:
            claims.append(
                {
                    "id": "neuralfoil_section",
                    "statement": (
                        "Section CL/CD from NeuralFoil ML surrogate at MAC Re; "
                        "not ARP6983 ML assurance case."
                    ),
                    "status": "supported_at_l1_surrogate",
                    "evidence": ["aero_l1"],
                }
            )
        if getattr(aero, "vspaero_used", False):
            claims.append(
                {
                    "id": "vspaero_vlm",
                    "statement": (
                        "Wing CL/CD from VSPAERO vortex-lattice (OpenVSP); "
                        f"fidelity={aero.fidelity}. Exploratory L1 VLM rank only — "
                        "not cert panel, not ARP6983, not flight clearance."
                    ),
                    "status": "supported_at_l1_vlm",
                    "evidence": ["aero_l1", "vspaero_l1"],
                }
            )
    else:
        claims.append(
            {
                "id": "rejected_or_infeasible",
                "statement": "Candidate rejected by runtime monitor or missing L1 eval.",
                "status": "unsupported",
                "evidence": ["monitor"],
            }
        )

    gsn_stub = {
        "top_goal": (
            "Produce a geometrically feasible wing with improved L1 L/D "
            "rank vs parent (offline search only)"
        ),
        "strategies": ["L0_monitor", "L1_aero_rank", "L1_vspaero_optional", "offline_search_only"],
        "solutions": ["strip_uas_v0"],
        "context": [
            "public_osint_gym",
            "not_certification",
            "faa_ai_assurance_vocabulary_only",
            "arp6983_vocabulary_only",
        ],
    }

    pack: dict[str, Any] = {
        "evidence_id": str(uuid.uuid4()),
        "schema": "strip_uas_v0.evidence.v1",
        "created_unix": time.time(),
        "episode_id": episode_id,
        "parent_id": parent_id,
        "step": step,
        "seed": seed,
        "software": {
            "strip_uas_v0": __version__,
            "python": platform.python_version(),
            "platform": platform.platform(),
        },
        "agent_class": "learned_offline",
        "odd": odd,
        "wing": wing.to_dict(),
        "l0": l0.to_dict(),
        "aero": None if aero is None else aero.to_dict(),
        "reward": reward,
        "action": action,
        "monitor": {"allow": monitor_allowed, "reason_codes": monitor_reasons},
        "claims": claims,
        "gsn_stub": gsn_stub,
    }
    pack["strip_assurance"] = strip_overlay(pack)
    return pack


def write_evidence(pack: dict[str, Any], directory: Path) -> Path:
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / f"{pack['evidence_id']}.json"
    path.write_text(json.dumps(pack, indent=2, sort_keys=True))
    return path
