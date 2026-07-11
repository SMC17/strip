#!/usr/bin/env python3
"""Promote openvsp_cmd_mesh_digest from an export-smoke.json into the fixture."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "fixtures" / "validation" / "openvsp" / "export-conformance.json"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("export_smoke", type=Path, help="export-smoke.json from OpenVSP CI")
    args = parser.parse_args()
    smoke = json.loads(args.export_smoke.read_text(encoding="utf-8"))
    digest = smoke.get("mesh_digest")
    if not digest or not str(digest).startswith("sha256:"):
        raise SystemExit(f"missing mesh_digest in {args.export_smoke}")
    if smoke.get("backend") != "openvsp_cmd":
        raise SystemExit(f"backend must be openvsp_cmd, got {smoke.get('backend')}")
    fixture = json.loads(FIXTURE.read_text(encoding="utf-8"))
    fixture["openvsp_cmd_mesh_digest"] = digest
    limitations = list(fixture.get("limitations", []))
    note = (
        f"openvsp_cmd_mesh_digest pinned from OpenVSP export "
        f"({smoke.get('triangle_count')} tris, ~{float(smoke.get('surface_area_m2', 0)):.1f} m2)."
    )
    limitations = [item for item in limitations if "openvsp_cmd_mesh_digest pinned" not in item]
    limitations.append(note)
    fixture["limitations"] = limitations
    FIXTURE.write_text(json.dumps(fixture, indent=2) + "\n", encoding="utf-8")
    print(f"pinned {digest} into {FIXTURE}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
