#!/usr/bin/env python3
"""JSBSim static coefficient queries for shared linear-aero cross-implementation gates."""

from __future__ import annotations

import contextlib
import io
import json
import os
import sys

PROTOCOL = "strip.jsbsim-protocol.v0"


def aircraft_path() -> str:
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    return os.path.join(root, "vehicles", "jsbsim-linear-aero")


def query_coefficients(
    model: str,
    alpha_deg: float,
    beta_deg: float,
    vt_fps: float,
    altitude_ft: float,
) -> dict:
    import jsbsim

    buffer = io.StringIO()
    with contextlib.redirect_stdout(buffer), contextlib.redirect_stderr(buffer):
        # Pass the package directory explicitly (as jsbsim_atmosphere.py and
        # jsbsim_fixed_wing.py do). FGFDMExec(None) calls
        # jsbsim.get_default_root_dir(), which only searches
        # site.getsitepackages() and USER_SITE, so it raises OSError when the
        # wheel is importable via a .pth overlay (e.g. `uv run --with jsbsim`).
        fdm = jsbsim.FGFDMExec(os.path.dirname(jsbsim.__file__))
        fdm.set_aircraft_path(aircraft_path())
        if not fdm.load_model(model):
            raise RuntimeError(f"failed to load model {model}")
        fdm.set_property_value("ic/h-sl-ft", altitude_ft)
        fdm.set_property_value("ic/vt-fps", vt_fps)
        fdm.set_property_value("ic/alpha-deg", alpha_deg)
        fdm.set_property_value("ic/beta-deg", beta_deg)
        fdm.set_property_value("ic/theta-deg", alpha_deg)
        fdm.set_property_value("gear/gear-pos-norm", 0.0)
        fdm.run_ic()
        fdm.run()
        return {
            "schema": PROTOCOL,
            "backend": "jsbsim_python",
            "query": "fixed_wing_coefficients",
            "model": model,
            "alpha_rad": fdm.get_property_value("aero/alpha-rad"),
            "beta_rad": fdm.get_property_value("aero/beta-rad"),
            "mach": fdm.get_property_value("velocities/mach"),
            "cx": fdm.get_property_value("aero/strip-cx"),
            "cy": fdm.get_property_value("aero/strip-cy"),
            "cz": fdm.get_property_value("aero/strip-cz"),
            "cl": fdm.get_property_value("aero/strip-cl"),
            "cm": fdm.get_property_value("aero/strip-cm"),
            "cn": fdm.get_property_value("aero/strip-cn"),
        }


def main() -> int:
    if len(sys.argv) < 2 or sys.argv[1] != "coefficients":
        return 2
    line = sys.stdin.readline()
    if not line:
        return 2
    request = json.loads(line)
    if request.get("schema") != PROTOCOL or request.get("query") != "fixed_wing_coefficients":
        return 2
    response = query_coefficients(
        model=request.get("model", "linear-aero"),
        alpha_deg=float(request["alpha_deg"]),
        beta_deg=float(request.get("beta_deg", 0.0)),
        vt_fps=float(request.get("vt_fps", 100.0)),
        altitude_ft=float(request.get("altitude_ft", 1000.0)),
    )
    sys.stdout.write(json.dumps(response) + "\n")
    sys.stdout.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
