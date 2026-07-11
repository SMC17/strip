#!/usr/bin/env python3
"""Promote openvsp_cmd_mesh_digest from strip-mesh-digest output into the fixture."""

from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "fixtures" / "validation" / "openvsp" / "export-conformance.json"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("stl", type=Path, help="ASCII STL from OpenVSP export")
    parser.add_argument(
        "--mesh-digest-bin",
        default=str(ROOT / "zig-out" / "bin" / "strip-mesh-digest"),
        help="Path to strip-mesh-digest",
    )
    args = parser.parse_args()
    proc = subprocess.run(
        [args.mesh_digest_bin, str(args.stl)],
        check=True,
        capture_output=True,
        text=True,
    )
    digest = proc.stdout.splitlines()[0].strip()
    if not digest.startswith("sha256:"):
        raise SystemExit(f"unexpected digest output: {digest}")
    fixture = json.loads(FIXTURE.read_text(encoding="utf-8"))
    fixture["openvsp_cmd_mesh_digest"] = digest
    limitations = [
        item
        for item in fixture.get("limitations", [])
        if "openvsp_cmd_mesh_digest" not in item
    ]
    limitations.append(
        f"openvsp_cmd_mesh_digest is the Strip Zig mesh digest from {args.stl.name}."
    )
    fixture["limitations"] = limitations
    FIXTURE.write_text(json.dumps(fixture, indent=2) + "\n", encoding="utf-8")
    print(f"pinned {digest} into {FIXTURE}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
