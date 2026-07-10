#!/usr/bin/env python3
"""JSBSim atmosphere runner for Strip cross-implementation comparison.

Uses the installed jsbsim Python module (v1.3.x) with the bundled
weather-balloon model as a minimal atmosphere host. Density is derived
from modeled pressure and temperature via the ideal gas law because the
Python bindings do not expose a reliable in-situ density property.
"""

from __future__ import annotations

import json
import os
import sys

PROTOCOL = "strip.jsbsim-protocol.v0"
GAS_CONSTANT_AIR = 287.05287
PSF_TO_PA = 47.880208
RANKINE_TO_KELVIN = 5.0 / 9.0
FPS_TO_MPS = 0.3048


def query_atmosphere(geopotential_altitude_m: float) -> dict:
    import contextlib
    import io
    import jsbsim

    root = os.path.dirname(jsbsim.__file__)
    buffer = io.StringIO()
    with contextlib.redirect_stdout(buffer), contextlib.redirect_stderr(buffer):
        fdm = jsbsim.FGFDMExec(root)
        if not fdm.load_model("weather-balloon"):
            raise RuntimeError("failed to load weather-balloon model")

        altitude_ft = geopotential_altitude_m / 0.3048
        fdm.set_property_value("ic/h-sl-ft", altitude_ft)
        fdm.set_property_value("ic/vt-fps", 0.0)
        fdm.run_ic()
        fdm.run()

        temperature_k = fdm.get_property_value("atmosphere/T-R") * RANKINE_TO_KELVIN
        pressure_pa = fdm.get_property_value("atmosphere/P-psf") * PSF_TO_PA
        speed_of_sound_mps = fdm.get_property_value("atmosphere/a-fps") * FPS_TO_MPS
    density_kg_m3 = pressure_pa / (GAS_CONSTANT_AIR * temperature_k)

    return {
        "schema": PROTOCOL,
        "backend": "jsbsim_python",
        "jsbsim_version": "1.3.1",
        "temperature_k": temperature_k,
        "pressure_pa": pressure_pa,
        "density_kg_m3": density_kg_m3,
        "speed_of_sound_mps": speed_of_sound_mps,
    }


def main() -> int:
    if len(sys.argv) < 2 or sys.argv[1] != "atmosphere":
        return 2
    line = sys.stdin.readline()
    if not line:
        return 2
    request = json.loads(line)
    if request.get("schema") != PROTOCOL or request.get("query") != "atmosphere":
        return 2
    altitude_m = float(request["geopotential_altitude_m"])
    response = query_atmosphere(altitude_m)
    sys.stdout.write(json.dumps(response) + "\n")
    sys.stdout.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
