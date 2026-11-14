"""Strip assurance vocabulary overlay (public OSINT / FAA AI / ARP6983 honesty).

Maps Strip-UAS-v0 evidence packs onto Strip trust/evidence field names.
Does NOT claim FAA AI assurance approval, ARP6983 process conformance,
airworthiness, or operational authorization — vocabulary alignment only.
"""

from __future__ import annotations

from typing import Any


ASSURANCE_LEVELS = (
    "L0_reject",
    "L1_rank",
    "L2_panel",
    "L3_cfd",
    "L4_ops",
)  # L4 out of scope for this gym


def strip_overlay(evidence: dict[str, Any]) -> dict[str, Any]:
    """Attach a Strip-flavored assurance block to an evidence pack."""
    monitor_ok = evidence.get("monitor", {}).get("allow", False)
    l0_ok = evidence.get("l0", {}).get("feasible", False)
    aero = evidence.get("aero")
    has_l1 = aero is not None
    nf = bool(aero.get("neuralfoil_used")) if isinstance(aero, dict) else False

    acc = evidence.get("acceptance") or {}
    accepted = has_l1 and acc.get("passed") is True
    if not monitor_ok or not l0_ok:
        level = "L0_reject"
        disposition = "reject_before_eval"
    elif has_l1 and not accepted:
        level = "L0_reject"
        disposition = "reject_acceptance_gate"
    elif accepted:
        level = "L1_rank"
        disposition = "rank_only"
    else:
        level = "L0_reject"
        disposition = "incomplete"

    claims = evidence.get("claims") or []
    return {
        "schema": "strip_assurance.overlay.v0",
        "product_line": "strip_uas",
        "not_certification": True,
        "not_operational": True,
        "not_faa_ai_assurance_approval": True,
        "not_arp6983_conformance": True,
        "learning_in_ops": False,
        "assurance_level": level,
        "disposition": disposition,
        "odd_ref": "odd",
        "vocabulary": {
            "faa_ai_assurance": "terms_only_public_osint",
            "arp6983": "terms_only_public_osint",
            "gsn": "stub_only",
        },
        "claim_ids": [c.get("id") for c in claims if isinstance(c, dict)],
        "validation_gates": {
            "runtime_monitor": monitor_ok,
            "geometry_l0": l0_ok,
            "aero_l1": accepted and l0_ok,
            "acceptance_l1": accepted,
            "neuralfoil_l1": nf and l0_ok,
            "panel_l2": False,
            "cfd_l3": False,
            "openvsp_geometry": False,
            "jsbsim_fdm": False,
        },
        "next_gate": (
            "L2_openvsp_vspaero_or_jsbsim" if level == "L1_rank" else "repair_l0"
        ),
    }
