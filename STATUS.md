# Strip Status

Date: 2026-07-10

## Executable surface

- evidence kernel, canonical JSON subset, strict schemas, and public-use policy
- typed math, WGS84 transforms, simulation time, RNG, identity, and replay
- coupled 6-DOF rigid-body dynamics with RK4 load callbacks and Earth/gravity
- US76 atmosphere through 86 km, Dryden/von Kármán turbulence, wind, and weather contracts
- fixed-wing aerodynamics, propulsion, trim, linearization, maneuvers, and contact
- multirotor rotor/motor/battery physics, allocation, control, and estimation
- deterministic multi-rate runtime, scene composition, collision/CCD, and sensor timing
- perception timing, human-factor primitives, terrain, airports, and landing gear
- validation envelopes, source manifests (18 primary sources), coverage matrix, comparators
- flight-test telemetry, regression, residuals, maneuvers, HIL contracts, evidence packages
- typed interop contracts (FMI 3.0, MAVLink, HLA/DIS) and frontier adapter catalog
- assurance graph, constrained agent permissions, and product/frontier inventory

Proof level: `unit-tested`

Verification:

```sh
zig build verify
zig build test -Doptimize=ReleaseSafe
./zig-out/bin/strip atmosphere 1000 preliminary_design
./zig-out/bin/strip-validation
./zig-out/bin/strip-fidelity
```

Latest local gate: 202 unit tests plus UAS, assurance, platform, validation, fidelity,
and proof-gates integration executables.

## Proof gates (v2)

| Gate | Evidence tier | Honest limit |
|------|---------------|--------------|
| JSBSim atmosphere | `cross_implementation` via pip `jsbsim` | US76-class atmosphere; weather-balloon host |
| JSBSim fixed-wing | `cross_implementation` via F-16 short integration | JSBSim vehicle host; not Strip native aero tables |
| OpenVSP digest | pinned geometry manifest v3.42.0 | Canonical description; no linked OpenVSP runtime required |
| OpenVSP tessellation | analytic box-wing mesher | Mesh digest/area/count regression |
| OpenVSP export | `OPENSP_CMD` or `analytic_stl_exporter` | STL export conformance; not CFD suitability |
| Replay | pinned x86_64/linux; `pending_count` for aarch64/macos | Promote via `strip-promote-replay-baseline` + CI artifacts |
| Uncertainty analytic/MC | affine propagation + calibration | Synthetic affine + campaign holdout coverage |
| Flight evidence (Gate 5) | `software_only` framework | Sealed manifest + split policy; `operational_qualification_claimed: false` |

Proof gate runner:

```sh
JSBSIM_CMD=tools/jsbsim_cmd.sh zig build run-proof-gates
./zig-out/bin/strip-record-replay-baseline
cat baseline.json | ./zig-out/bin/strip-promote-replay-baseline > fixtures/validation/replay/rk4-cross-target.json
tools/promote_replay_from_ci.sh baseline.json
```

Latest local gate: 208 unit tests plus integration executables and proof-gates v2.

## Next proof work

- public license
- promote aarch64/linux and macOS replay baselines from CI matrix artifacts
- wire real `OPENSP_CMD` OpenVSP 3.42.0 CAD export when binary available in CI
- JSBSim fixed-wing comparison against Strip native coefficient provider at matched conditions
- ingest NASA TP-1538 coefficient tables and expand vehicle cross-check envelope

## Scaffold-level contracts

- JSBSim, OpenVSP, OpenMDAO, ROS 2/DDS, CARLA, PhysX, OpenUSD, Project AirSim,
  PX4/ArduPilot adapters
- WorldForge generation, DesignEvolve search, rare-event sampling,
  multi-fidelity scheduling, live digital twins, and learned models
- browser product interfaces

These contracts compile and have boundary tests; no linked external system or
validated frontier model is claimed.
