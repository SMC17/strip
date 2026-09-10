"""VSPAERO L1 aero teacher (Strip air path).

Runs a parametric trapezoidal wing through ``vspscript`` analyses:

1. ``VSPAEROComputeGeometry``
2. ``VSPAEROSweep`` (single alpha)

Parses printed markers (``strip_uas_CL=…``) and optionally ``*.polar``.

Requires vendored OpenVSP CLI (``vspscript`` + ``vspaero``) under
``vendor/openvsp`` — see ``docs/OPENVSP_INSTALL.md`` / Yard twin.

Fidelity: exploratory vortex-lattice ranking only.
Not certification, not operational, not FAA / ARP6983.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any

FIDELITY_PENDING = "aero_vspaero_pending"
FIDELITY = "aero_vspaero_l1"
TEACHER = "vspaero_l1"

_PKG_FILE = Path(__file__).resolve()
# teachers/ -> package -> gym-or-repo root (strip-uas-v0 or tools/gym)
_REPO_CANDIDATES = [
    _PKG_FILE.parents[2],  # local: strip-uas-v0 ; on strip: tools/gym
    _PKG_FILE.parents[3] if len(_PKG_FILE.parents) > 3 else _PKG_FILE.parents[2],
    _PKG_FILE.parents[4] if len(_PKG_FILE.parents) > 4 else _PKG_FILE.parents[2],
]

_MARKER_RE = re.compile(
    r"strip_uas_(CL|CD|CM)=([-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?)"
)

# AngelScript: parametric wing + VSPAEROComputeGeometry + single-point VSPAEROSweep.
# Placeholders replaced before write.
_VSPAERO_SCRIPT = r"""void main()
{
    Print( string( "strip_uas_vspaero_start" ) );
    ClearVSPModel();
    Update();

    string wing_id = AddGeom( "WING", "" );
    SetGeomName( wing_id, "StripWing" );

    SetDriverGroup( wing_id, 1, AREA_WSECT_DRIVER, ROOTC_WSECT_DRIVER, TIPC_WSECT_DRIVER );
    SetParmVal( wing_id, "Root_Chord", "XSec_1", ROOT_CHORD_PLACEHOLDER );
    SetParmVal( wing_id, "Tip_Chord", "XSec_1", TIP_CHORD_PLACEHOLDER );
    SetParmVal( wing_id, "Area", "XSec_1", AREA_PLACEHOLDER );
    SetParmVal( wing_id, "Sweep", "XSec_1", SWEEP_PLACEHOLDER );
    SetParmVal( wing_id, "Twist", "XSec_1", TWIST_PLACEHOLDER );
    SetParmVal( wing_id, "Tess_W", "Shape", 33 );
    SetParmVal( wing_id, "SectTess_U", "XSec_1", 8 );
    Update();

    WriteVSPFile( "strip_uas_vspaero.vsp3", SET_ALL );
    ClearVSPModel();
    Update();
    ReadVSPFile( "strip_uas_vspaero.vsp3" );
    Update();

    string compgeom_name = "VSPAEROComputeGeometry";
    SetAnalysisInputDefaults( compgeom_name );
    Print( string( "strip_uas_compgeom_exec" ) );
    string compgeom_resid = ExecAnalysis( compgeom_name );
    Print( string( "strip_uas_compgeom_done" ) );

    string analysis_name = "VSPAEROSweep";
    SetAnalysisInputDefaults( analysis_name );

    array<int> geom_set;
    geom_set.push_back( 0 );
    SetIntAnalysisInput( analysis_name, "GeomSet", geom_set, 0 );

    array<int> ref_flag;
    ref_flag.push_back( 1 );
    SetIntAnalysisInput( analysis_name, "RefFlag", ref_flag, 0 );

    array<string> wid = FindGeomsWithName( "StripWing" );
    if ( wid.length() == 0 )
    {
        wid = FindGeomsWithName( "WingGeom" );
    }
    if ( wid.length() > 0 )
    {
        SetStringAnalysisInput( analysis_name, "WingID", wid, 0 );
    }

    array<double> alpha;
    alpha.push_back( ALPHA_PLACEHOLDER );
    SetDoubleAnalysisInput( analysis_name, "AlphaStart", alpha, 0 );
    array<int> alphaNpts;
    alphaNpts.push_back( 1 );
    SetIntAnalysisInput( analysis_name, "AlphaNpts", alphaNpts, 0 );

    array<double> mach;
    mach.push_back( 0.1 );
    SetDoubleAnalysisInput( analysis_name, "MachStart", mach, 0 );
    array<int> machNpts;
    machNpts.push_back( 1 );
    SetIntAnalysisInput( analysis_name, "MachNpts", machNpts, 0 );

    array<int> ncpu;
    ncpu.push_back( 1 );
    SetIntAnalysisInput( analysis_name, "NCPU", ncpu, 0 );

    array<int> wakeIters;
    wakeIters.push_back( 3 );
    SetIntAnalysisInput( analysis_name, "WakeNumIter", wakeIters, 0 );

    Update();
    Print( string( "strip_uas_sweep_exec" ) );
    string rid = ExecAnalysis( analysis_name );
    Print( string( "strip_uas_sweep_done" ) );

    string history_res = FindLatestResultsID( "VSPAERO_History" );
    Print( string( "strip_uas_history_id=" ) + history_res );

    array<double> CL = GetDoubleResults( history_res, "CLtot", 0 );
    array<double> CD = GetDoubleResults( history_res, "CDtot", 0 );
    array<double> CMy = GetDoubleResults( history_res, "CMytot", 0 );

    if ( CL.length() == 0 ) { CL = GetDoubleResults( history_res, "CL", 0 ); }
    if ( CD.length() == 0 ) { CD = GetDoubleResults( history_res, "CD", 0 ); }
    if ( CMy.length() == 0 ) { CMy = GetDoubleResults( history_res, "CMy", 0 ); }

    double cl_v = 0.0;
    double cd_v = 0.0;
    double cm_v = 0.0;
    if ( CL.length() > 0 ) { cl_v = CL[ int(CL.length()) - 1 ]; }
    if ( CD.length() > 0 ) { cd_v = CD[ int(CD.length()) - 1 ]; }
    if ( CMy.length() > 0 ) { cm_v = CMy[ int(CMy.length()) - 1 ]; }

    Print( string( "strip_uas_CL=" ) + cl_v );
    Print( string( "strip_uas_CD=" ) + cd_v );
    Print( string( "strip_uas_CM=" ) + cm_v );
    Print( string( "strip_uas_vspaero_ok" ) );

    while ( GetNumTotalErrors() > 0 )
    {
        ErrorObj err = PopLastError();
        Print( err.GetErrorString() );
    }
}
"""


@dataclass
class VSPAEROAvailability:
    vspscript: str | None = None
    vspaero: str | None = None
    version: str | None = None
    vendor_root: str | None = None

    @property
    def available(self) -> bool:
        return bool(self.vspscript and self.vspaero)

    def to_dict(self) -> dict[str, Any]:
        return {
            "vspscript": self.vspscript,
            "vspaero": self.vspaero,
            "version": self.version,
            "vendor_root": self.vendor_root,
            "available": self.available,
            "install_hint": (
                "Prefer vendor/openvsp from Ubuntu .deb extract "
                "(docs/OPENVSP_INSTALL.md). Need both vspscript and vspaero. "
                "Or set STRIP_OPENVSP_VENDOR / OPENVSP_HOME."
            ),
        }


def _vendor_roots() -> list[Path]:
    roots: list[Path] = []
    for key in ("STRIP_OPENVSP_VENDOR", "OPENVSP_HOME", "OPENVSP_VENDOR"):
        raw = os.environ.get(key)
        if raw:
            roots.append(Path(raw))
    for base in _REPO_CANDIDATES:
        roots.append(base / "vendor" / "openvsp")
    # Sibling Yard-Sea checkout (shared box / monorepo-adjacent)
    for base in _REPO_CANDIDATES:
        roots.append(base.parent / "yard-sea-v0" / "vendor" / "openvsp")
        roots.append(base / "yard-sea-v0" / "vendor" / "openvsp")
    # de-dupe
    seen: set[str] = set()
    out: list[Path] = []
    for p in roots:
        try:
            key = str(p.resolve()) if p.exists() else str(p)
        except OSError:
            key = str(p)
        if key not in seen:
            seen.add(key)
            out.append(p)
    return out


def _find_exe(name: str) -> tuple[Path | None, Path | None]:
    """Return (exe, vendor_root_used)."""
    for root in _vendor_roots():
        cand = root / name
        if cand.is_file() and os.access(cand, os.X_OK):
            return cand, root
    which = shutil.which(name)
    if which:
        return Path(which), Path(which).resolve().parent
    return None, None


def detect() -> VSPAEROAvailability:
    """Probe vendor/PATH for vspscript + vspaero (no side effects)."""
    vspscript, root_a = _find_exe("vspscript")
    vspaero, root_b = _find_exe("vspaero")
    version = "cli" if vspscript else None
    vendor = root_a or root_b
    return VSPAEROAvailability(
        vspscript=str(vspscript) if vspscript else None,
        vspaero=str(vspaero) if vspaero else None,
        version=version,
        vendor_root=str(vendor) if vendor else None,
    )


def parse_markers(text: str) -> dict[str, float | None]:
    """Parse ``strip_uas_CL/CD/CM=`` markers from vspscript stdout."""
    out: dict[str, float | None] = {"CL": None, "CD": None, "CM": None}
    for key, val in _MARKER_RE.findall(text):
        try:
            out[key] = float(val)
        except ValueError:
            continue
    return out


def parse_polar(path: Path) -> dict[str, float | None]:
    """Parse last data row of a VSPAERO ``*.polar`` for CLtot/CDtot/CMytot."""
    empty: dict[str, float | None] = {"CL": None, "CD": None, "CM": None}
    if not path.is_file():
        return empty
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    header_idx = None
    headers: list[str] = []
    for i, line in enumerate(lines):
        toks = line.split()
        if toks and toks[0] == "Beta" and "CLtot" in toks and "CDtot" in toks:
            header_idx = i
            headers = toks
            break
    if header_idx is None:
        return empty
    try:
        i_cl = headers.index("CLtot")
        i_cd = headers.index("CDtot")
        i_cm = headers.index("CMytot")
    except ValueError:
        return empty
    data_row = None
    for line in lines[header_idx + 1 :]:
        toks = line.split()
        if len(toks) <= max(i_cl, i_cd, i_cm):
            continue
        try:
            float(toks[0])
        except ValueError:
            continue
        data_row = toks
    if data_row is None:
        return empty
    try:
        return {
            "CL": float(data_row[i_cl]),
            "CD": float(data_row[i_cd]),
            "CM": float(data_row[i_cm]),
        }
    except (ValueError, IndexError):
        return empty


def _env_with_vendor(vspscript: str) -> dict[str, str]:
    env = os.environ.copy()
    vend = str(Path(vspscript).resolve().parent)
    prev = env.get("PATH", "")
    if vend not in prev.split(os.pathsep):
        env["PATH"] = vend + os.pathsep + prev
    return env


def _wing_params(
    *,
    span_m: float = 2.4,
    chord_root_m: float = 0.30,
    taper: float = 0.70,
    sweep_deg: float = 5.0,
    twist_deg: float = -2.0,
    alpha_deg: float = 2.0,
) -> dict[str, float]:
    tip = max(1e-4, chord_root_m * taper)
    root = max(1e-4, chord_root_m)
    span = max(1e-3, span_m)
    area = span * 0.5 * (root + tip)
    return {
        "root_chord": root,
        "tip_chord": tip,
        "area": area,
        "sweep": float(sweep_deg),
        "twist": float(twist_deg),
        "alpha": float(alpha_deg),
        "span": span,
    }


def _render_script(params: dict[str, float]) -> str:
    body = _VSPAERO_SCRIPT
    repl = {
        "ROOT_CHORD_PLACEHOLDER": f"{params['root_chord']:.8f}",
        "TIP_CHORD_PLACEHOLDER": f"{params['tip_chord']:.8f}",
        "AREA_PLACEHOLDER": f"{params['area']:.8f}",
        "SWEEP_PLACEHOLDER": f"{params['sweep']:.8f}",
        "TWIST_PLACEHOLDER": f"{params['twist']:.8f}",
        "ALPHA_PLACEHOLDER": f"{params['alpha']:.8f}",
    }
    for k, v in repl.items():
        body = body.replace(k, v)
    return body


def _run_vspaero_script(
    vspscript: str,
    work: Path,
    *,
    params: dict[str, float],
    timeout_sec: float = 120.0,
) -> dict[str, Any]:
    work = work.resolve()
    work.mkdir(parents=True, exist_ok=True)
    script_path = work / "strip_uas_vspaero.vspscript"
    script_path.write_text(_render_script(params), encoding="utf-8")

    proc = subprocess.run(
        [vspscript, "-script", script_path.name],
        cwd=str(work),
        capture_output=True,
        text=True,
        timeout=timeout_sec,
        check=False,
        env=_env_with_vendor(vspscript),
    )
    combined = (proc.stdout or "") + "\n" + (proc.stderr or "")
    markers = parse_markers(combined)
    polar = parse_polar(work / "strip_uas_vspaero.polar")

    cl = markers["CL"] if markers["CL"] is not None else polar["CL"]
    cd = markers["CD"] if markers["CD"] is not None else polar["CD"]
    cm = markers["CM"] if markers["CM"] is not None else polar["CM"]

    ok_marker = "strip_uas_vspaero_ok" in combined
    wrote_vsp3 = (work / "strip_uas_vspaero.vsp3").is_file()
    compile_err = "Error ExecuteScript" in combined or " : ERR  :" in combined
    have_coeffs = cl is not None and cd is not None and cm is not None

    return {
        "returncode": proc.returncode,
        "stdout": proc.stdout or "",
        "stderr": proc.stderr or "",
        "ok_marker": ok_marker,
        "wrote_vsp3": wrote_vsp3,
        "compile_err": compile_err,
        "CL": cl,
        "CD": cd,
        "CM": cm,
        "source": (
            "markers"
            if markers["CL"] is not None
            else ("polar" if polar["CL"] is not None else None)
        ),
        "success": bool(ok_marker and have_coeffs and not compile_err),
        "vsp3_bytes": (
            (work / "strip_uas_vspaero.vsp3").stat().st_size if wrote_vsp3 else 0
        ),
        "params": params,
    }


def _skip_payload(
    *,
    reason: str,
    alpha_deg: float,
    avail: VSPAEROAvailability,
    model_path: str | None,
    notes: str,
    detail: dict[str, Any] | None = None,
) -> dict[str, Any]:
    out: dict[str, Any] = {
        "teacher": TEACHER,
        "skipped": True,
        "skip_reason": reason,
        "fidelity": FIDELITY_PENDING,
        "CL": None if detail is None else detail.get("CL"),
        "CD": None if detail is None else detail.get("CD"),
        "CM": None if detail is None else detail.get("CM"),
        "LD": None,
        "alpha_deg": alpha_deg,
        "model_path": model_path,
        "availability": avail.to_dict(),
        "notes": notes,
    }
    if detail is not None:
        out["cli"] = {
            "bin": avail.vspscript,
            "returncode": detail.get("returncode"),
            "ok_marker": detail.get("ok_marker"),
            "wrote_vsp3": detail.get("wrote_vsp3"),
            "compile_err": detail.get("compile_err"),
        }
    return out


def run(
    *,
    alpha_deg: float = 2.0,
    span_m: float = 2.4,
    chord_root_m: float = 0.30,
    taper: float = 0.70,
    sweep_deg: float = 5.0,
    twist_deg: float = -2.0,
    availability: VSPAEROAvailability | None = None,
    work_dir: str | None = None,
    model_path: str | None = None,
    timeout_sec: float = 120.0,
) -> dict[str, Any]:
    """Run parametric-wing VSPAERO via vspscript; skip cleanly if unavailable."""
    avail = availability if availability is not None else detect()
    params = _wing_params(
        span_m=span_m,
        chord_root_m=chord_root_m,
        taper=taper,
        sweep_deg=sweep_deg,
        twist_deg=twist_deg,
        alpha_deg=alpha_deg,
    )
    if not avail.available:
        return _skip_payload(
            reason="vspaero_unavailable",
            alpha_deg=alpha_deg,
            avail=avail,
            model_path=model_path,
            notes=(
                "VSPAERO L1 teacher — vspscript/vspaero absent. "
                "Not cert / not operational."
            ),
        )

    assert avail.vspscript is not None
    try:
        if work_dir:
            work = Path(work_dir)
            work.mkdir(parents=True, exist_ok=True)
            detail = _run_vspaero_script(
                avail.vspscript, work, params=params, timeout_sec=timeout_sec
            )
        else:
            with tempfile.TemporaryDirectory(prefix="strip_vspaero_") as td:
                detail = _run_vspaero_script(
                    avail.vspscript,
                    Path(td),
                    params=params,
                    timeout_sec=timeout_sec,
                )
    except subprocess.TimeoutExpired:
        return _skip_payload(
            reason="vspaero_timeout",
            alpha_deg=alpha_deg,
            avail=avail,
            model_path=model_path,
            notes="VSPAERO vspscript timed out. Not cert / not operational.",
        )
    except Exception as exc:
        return _skip_payload(
            reason=f"run_error:{type(exc).__name__}",
            alpha_deg=alpha_deg,
            avail=avail,
            model_path=model_path,
            notes=f"VSPAERO run failed: {exc}. Not cert / not operational.",
        )

    if not detail["success"]:
        return _skip_payload(
            reason="vspaero_script_failed",
            alpha_deg=alpha_deg,
            avail=avail,
            model_path=model_path,
            notes=(
                "VSPAERO vspscript ran but CL/CD/CM not recovered. "
                "Not cert / not operational."
            ),
            detail=detail,
        )

    cl = float(detail["CL"])
    cd = float(max(detail["CD"], 1e-9))
    cm = float(detail["CM"])
    ld = cl / cd
    return {
        "teacher": TEACHER,
        "skipped": False,
        "skip_reason": None,
        "fidelity": FIDELITY,
        "CL": cl,
        "CD": cd,
        "CM": cm,
        "LD": ld,
        "alpha_deg": alpha_deg,
        "wing": {
            "span_m": span_m,
            "chord_root_m": chord_root_m,
            "taper": taper,
            "sweep_deg": sweep_deg,
            "twist_deg": twist_deg,
            "area_m2": params["area"],
        },
        "model_path": model_path,
        "availability": avail.to_dict(),
        "cli": {
            "bin": avail.vspscript,
            "vspaero": avail.vspaero,
            "returncode": detail["returncode"],
            "vsp3_bytes": detail["vsp3_bytes"],
            "coeff_source": detail["source"],
        },
        "notes": (
            "VSPAERO L1 parametric wing OK "
            "(VSPAEROComputeGeometry + VSPAEROSweep @ "
            f"alpha={alpha_deg} deg). Vortex-lattice exploratory only. "
            "Not cert / not operational / not ARP6983."
        ),
    }


def run_for_wing(wing: Any, **kwargs: Any) -> dict[str, Any]:
    """Convenience: pull particulars from a WingState-like object."""
    return run(
        alpha_deg=float(getattr(wing, "alpha_deg", 2.0)),
        span_m=float(getattr(wing, "span_m", 2.4)),
        chord_root_m=float(getattr(wing, "chord_root_m", 0.30)),
        taper=float(getattr(wing, "taper", 0.70)),
        sweep_deg=float(getattr(wing, "sweep_deg", 5.0)),
        twist_deg=float(getattr(wing, "twist_deg", -2.0)),
        **kwargs,
    )


def run_teacher(**kwargs: Any) -> dict[str, Any]:
    return run(**kwargs)
