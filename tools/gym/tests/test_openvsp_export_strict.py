"""tools/openvsp_export.py stays strict: nonzero exit, API errors or a missing
completion marker all fail the export (fake OPENSP_CMD, no OpenVSP needed)."""

from __future__ import annotations

import importlib.util
import stat
from pathlib import Path

import pytest

TOOLS = Path(__file__).resolve().parents[2]


def _load():
    spec = importlib.util.spec_from_file_location("strip_openvsp_export", TOOLS / "openvsp_export.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


STL = "solid t\\nfacet normal 0 0 1\\nouter loop\\nvertex 0 0 0\\nvertex 1 0 0\\nvertex 0 1 0\\nendloop\\nendfacet\\nendsolid t\\n"


def _fake(tmp_path: Path, *, out: str, rc: int, write: bool = True) -> str:
    # The fake reads the output path the wrapper substituted into the script.
    body = (
        "#!/bin/sh\n"
        'OUT=$(sed -n \'s/.*string out_path = "\\(.*\\)";.*/\\1/p\' "$2")\n'
        + (f'printf "{STL}" > "$OUT"\n' if write else "")
        + f"printf '%s\\n' \"{out}\"\nexit {rc}\n"
    )
    p = tmp_path / "fake_vsp"
    p.write_text(body)
    p.chmod(p.stat().st_mode | stat.S_IXUSR)
    return str(p)


def _req(tmp_path):
    return {"output_path": str(tmp_path / "o.stl")}


def test_clean_export_accepted(tmp_path, monkeypatch):
    monkeypatch.setenv("DISPLAY", ":0")
    m = _load()
    r = m.openvsp_export(_req(tmp_path), _fake(tmp_path, out="strip_vsp_api_errors=0 strip_vsp_export_ok", rc=0))
    assert r["backend"] == "openvsp_cmd" and r["triangle_count"] == 1


def test_nonzero_exit_rejected_even_with_marker(tmp_path, monkeypatch):
    monkeypatch.setenv("DISPLAY", ":0")
    m = _load()
    with pytest.raises(RuntimeError, match="exited 2"):
        m.openvsp_export(_req(tmp_path), _fake(tmp_path, out="strip_vsp_export_ok", rc=2))


def test_api_errors_rejected(tmp_path, monkeypatch):
    monkeypatch.setenv("DISPLAY", ":0")
    m = _load()
    out = "Error Code: 4, Desc: SetParmVal::Can't Find Parm X:Design:Span strip_vsp_export_ok"
    with pytest.raises(RuntimeError, match="API error"):
        m.openvsp_export(_req(tmp_path), _fake(tmp_path, out=out, rc=0))


def test_missing_marker_rejected(tmp_path, monkeypatch):
    monkeypatch.setenv("DISPLAY", ":0")
    m = _load()
    with pytest.raises(RuntimeError, match="strip_vsp_export_ok"):
        m.openvsp_export(_req(tmp_path), _fake(tmp_path, out="done", rc=0))


def test_template_returns_int_exit_code():
    t = (TOOLS / "openvsp_box_wing.vspscript").read_text()
    assert "\nint main()" in t and "\nvoid main()" not in t
    assert "return 0;" in t
    assert '"Design", 10.0' not in t and '"XSec_1"' in t
