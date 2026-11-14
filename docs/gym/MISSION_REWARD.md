# Strip-UAS-v0 multi-point mission reward (`mission_multipoint_v0`)

Module: `tools/gym/strip_uas_v0/mission.py`; enable with
`DesignSearchEnv(mission=Mission())` (default `None` keeps the single-alpha L/D reward).

Each wing is trimmed (regula falsi on the L1 oracle's alpha, inside the wing alpha band)
to `CL_req = m·g/(½ρV²S)` at each point, same mass throughout:

| Point (default) | V | Figure of merit |
|---|---|---|
| cruise | 22 m/s | L/D (range proxy, higher better) |
| climb | 16 m/s | D·V power required in level flight (excess-power proxy, lower better) |
| loiter | 13 m/s | CL^1.5/CD (propeller endurance proxy, higher better) |

`score = weighted_mean(d) + worst_case_weight·min(0, min d)`, `d` = relative improvement
vs. parent. A point is credited only when both wings trim inside the band and pass the
aero acceptance gate at the same fidelity; otherwise the env reward is −1.

Example (analytic L1 polar, 5 kg): span 2.4→3.0 m with root chord 0.33 m improves climb
+16% and loiter +12% but loses cruise L/D −3%; the worst-case term pulls the score from
+0.085 (mean) to +0.055.

Limits: wing alone (no fuselage/tail/prop drag), sea-level ISA, quasi-steady, mass and
speeds are conventions, L1 wing CL lacks a finite-span lift-slope correction (trim
alphas optimistic), and the NeuralFoil path ignores `tc` (default Kulfan section), so
thickness changes score zero there. Not a performance prediction; not FAA / ARP6983.
