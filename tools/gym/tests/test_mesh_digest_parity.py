"""Exporter mesh_digest == Zig strip-mesh-digest (canonical, gate-enforced)."""

from __future__ import annotations

import importlib.util
import json
import random
import subprocess
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[3]
ZIG_DIGEST = REPO / "zig-out" / "bin" / "strip-mesh-digest"


def _load():
    spec = importlib.util.spec_from_file_location("strip_openvsp_export_d", REPO / "tools" / "openvsp_export.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _stl(path: Path, coords: list[str]) -> Path:
    lines = ["solid t"]
    for i in range(0, len(coords), 9):
        lines += ["facet normal 0 0 0", "outer loop"]
        lines += [f"vertex {coords[i + j]} {coords[i + j + 1]} {coords[i + j + 2]}" for j in (0, 3, 6)]
        lines += ["endloop", "endfacet"]
    path.write_text("\n".join(lines) + "\nendsolid t\n")
    return path


# Pinned from Zig strip-mesh-digest so parity is checked even without a Zig build.
# Ties (…5 in the 10th place) are where Python's f"{v:.9f}" and Zig {d:.9} disagree.
TIES = ["0.1234567895", "1.0000000005", "-2.5000000005", "0.0000000005", "-0.0000000015",
        "-0", "1e-12", "-1e-12", "3"]
TIES_ZIG_DIGEST = "sha256:ab87e03318228529f421cddf21f799c412fbb990d21f193d8a0bbaa2e1d9a3f6"
MANIFEST = json.loads((REPO / "fixtures/validation/openvsp/export-conformance.json").read_text())


def test_ties_round_like_zig_not_like_python_format(tmp_path):
    m = _load()
    assert m.canonical_mesh_coord(0.1234567895) == "0.123456790|"  # Zig: half-up on shortest repr
    assert f"{0.1234567895:.9f}" == "0.123456789"  # what the old exporter hashed
    assert m.canonical_mesh_coord(-2.5000000005) == "-2.500000001|"
    assert m.canonical_mesh_coord(-0.0) == "-0.000000000|"
    assert m.canonical_mesh_coord(-1e-12) == "-0.000000000|"
    assert m.canonical_mesh_coord(1e10) == "10000000000.000000000|"
    assert m.mesh_metrics(str(_stl(tmp_path / "t.stl", TIES)))["mesh_digest"] == TIES_ZIG_DIGEST


def test_analytic_export_matches_manifest_pin(tmp_path):
    m = _load()
    out = m.analytic_export({"output_path": str(tmp_path / "ref.stl")})
    assert out["mesh_digest"] == MANIFEST["expected_mesh_digest"]
    assert out["triangle_count"] == MANIFEST["expected_triangle_count"]
    assert out["mesh_digest_method"] == m.MESH_DIGEST_METHOD


def test_non_finite_and_empty_meshes_rejected(tmp_path):
    m = _load()
    with pytest.raises(ValueError):
        m.canonical_mesh_coord(float("nan"))
    empty = tmp_path / "e.stl"
    empty.write_text("solid e\nendsolid e\n")
    with pytest.raises(ValueError):
        m.mesh_metrics(str(empty))


def _zig_digest(path: Path) -> str:
    return subprocess.run([str(ZIG_DIGEST), str(path)], check=True, capture_output=True, text=True).stdout.split()[0]


@pytest.mark.skipif(not ZIG_DIGEST.is_file(), reason="zig build not run (zig-out/bin/strip-mesh-digest)")
def test_cross_check_against_zig_binary(tmp_path):
    m = _load()
    rng = random.Random(1)
    cases = [TIES]
    for _ in range(60):
        row = []
        for _ in range(9):
            k = rng.random()
            if k < 0.3:
                row.append(f"{rng.uniform(-50, 50):.{rng.randint(6, 12)}f}")
            elif k < 0.55:
                row.append(f"{rng.uniform(-1, 1):.9f}" + "5")
            elif k < 0.75:
                row.append(f"{rng.uniform(-1e4, 1e4):.6e}")
            else:
                row.append(repr(rng.uniform(-100, 100)))
        cases.append(row)
    for i, coords in enumerate(cases):
        p = _stl(tmp_path / f"c{i}.stl", coords)
        assert m.mesh_metrics(str(p))["mesh_digest"] == _zig_digest(p), coords
    ref = tmp_path / "ref.stl"
    out = m.analytic_export({"output_path": str(ref)})
    assert out["mesh_digest"] == _zig_digest(ref)
