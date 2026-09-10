"""Optional aero teachers (NeuralFoil L1, OpenVSP geometry, JSBSim FDM).

Teacher protocol (shared with Yard-Sea-v0)
-----------------------------------------
Every teacher module exposes:

* ``detect() -> Availability`` — side-effect-free probe (PATH / import / vendor).
* ``run(...) -> dict`` — evaluate or **skip cleanly**.
* ``run_teacher(...)`` — alias of ``run``.

Honesty: never claim FAA certification, ARP6983 compliance, flight clearance,
or operational approval. NeuralFoil / OpenVSP / JSBSim are exploratory oracles.
"""

from . import jsbsim_stub
from . import neuralfoil_stub
from . import openvsp_stub

__all__ = [
    "jsbsim_stub",
    "neuralfoil_stub",
    "openvsp_stub",
]
