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

## Proof gates (v1)

| Gate | Evidence tier | Honest limit |
|------|---------------|--------------|
| JSBSim | `cross_implementation` when `JSBSIM_CMD` resolves to `tools/jsbsim_cmd.sh` + pip `jsbsim`; `subprocess_shim` otherwise | Python weather-balloon host; not a fixed-wing vehicle cross-check |
| OpenVSP digest | pinned geometry manifest v3.42.0 | Canonical description only; no linked OpenVSP runtime |
| OpenVSP tessellation | analytic box-wing mesher | Mesh digest/area/count; not CAD export or CFD suitability |
| Replay | pinned x86_64/linux Debug+ReleaseSafe; `pending` aarch64/linux and macOS | Multi-arch CI matrix records baselines; not cross-arch certification |
| Uncertainty | analytic affine propagation + Monte Carlo calibration + flight-data fusion | Not operational calibration against flight-test campaigns |

Proof gate runner:

```sh
JSBSIM_CMD=tools/jsbsim_cmd.sh zig build run-proof-gates
./zig-out/bin/strip-record-replay-baseline   # emit manifest case for current target
zig build gen-proof-fixtures                 # regenerate pinned digests
```

## Next proof work

- public license
- pin aarch64/linux and macOS replay baselines from CI matrix output
- wire `OPENSP_CMD` for subprocess CAD export conformance (beyond analytic mesher)
- JSBSim fixed-wing vehicle model comparison (beyond atmosphere host)
- full scenario-schema ingestion and canonical evidence-package export

## Scaffold-level contracts

- JSBSim, OpenVSP, OpenMDAO, ROS 2/DDS, CARLA, PhysX, OpenUSD, Project AirSim,
  PX4/ArduPilot adapters
- WorldForge generation, DesignEvolve search, rare-event sampling,
  multi-fidelity scheduling, live digital twins, and learned models
- browser product interfaces

These contracts compile and have boundary tests; no linked external system or
validated frontier model is claimed.
