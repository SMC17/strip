#!/usr/bin/env python3
"""JSBSim fixed-wing short-horizon integration for Strip cross-implementation gates.

Uses the bundled F-16 model as a production fixed-wing dynamics host. This is
not Strip-native vehicle physics; it validates subprocess integration and
pinned state evolution against a published fixture.
"""

from __future__ import annotations

import contextlib
import io
import json
import os
import sys

PROTOCOL = "strip.jsbsim-protocol.v0"
FPS_TO_MPS = 0.3048
FT_TO_M = 0.3048


def integrate_fixed_wing(
    model: str,
    altitude_ft: float,
    vt_fps: float,
    alpha_deg: float,
    theta_deg: float,
    steps: int,
) -> dict:
    import jsbsim

    root = os.path.dirname(jsbsim.__file__)
    buffer = io.StringIO()
    with contextlib.redirect_stdout(buffer), contextlib.redirect_stderr(buffer):
        fdm = jsbsim.FGFDMExec(root)
        if not fdm.load_model(model):
            raise RuntimeError(f"failed to load model {model}")
        fdm.set_property_value("ic/h-sl-ft", altitude_ft)
        fdm.set_property_value("ic/vt-fps", vt_fps)
        fdm.set_property_value("ic/alpha-deg", alpha_deg)
        fdm.set_property_value("ic/theta-deg", theta_deg)
        fdm.set_property_value("ic/beta-deg", 0.0)
        fdm.set_property_value("gear/gear-pos-norm", 0.0)
        fdm.run_ic()
        if steps < 1 or steps > 10_000:
            raise ValueError("steps out of range")
        for _ in range(steps):
            fdm.run()
        return {
            "schema": PROTOCOL,
            "backend": "jsbsim_python",
            "query": "fixed_wing_integrate",
            "model": model,
            "steps": steps,
            "altitude_m": fdm.get_property_value("position/h-sl-ft") * FT_TO_M,
            "vt_mps": fdm.get_property_value("velocities/vt-fps") * FPS_TO_MPS,
            "alpha_deg": fdm.get_property_value("aero/alpha-deg"),
            "theta_deg": fdm.get_property_value("attitude/theta-deg"),
            "q_radps": fdm.get_property_value("velocities/q-rad_sec"),
            "ax_mps2": fdm.get_property_value("accelerations/a-pilot-x-ft_sec2") * FT_TO_M,
            "az_mps2": fdm.get_property_value("accelerations/a-pilot-z-ft_sec2") * FT_TO_M,
            "qdot_radps2": fdm.get_property_value("accelerations/qdot-rad_sec2"),
        }


def main() -> int:
    if len(sys.argv) < 2 or sys.argv[1] != "fixed-wing":
        return 2
    line = sys.stdin.readline()
    if not line:
        return 2
    request = json.loads(line)
    if request.get("schema") != PROTOCOL or request.get("query") != "fixed_wing_integrate":
        return 2
    response = integrate_fixed_wing(
        model=request.get("model", "f16"),
        altitude_ft=float(request["altitude_ft"]),
        vt_fps=float(request["vt_fps"]),
        alpha_deg=float(request["alpha_deg"]),
        theta_deg=float(request["theta_deg"]),
        steps=int(request.get("steps", 50)),
    )
    sys.stdout.write(json.dumps(response) + "\n")
    sys.stdout.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
