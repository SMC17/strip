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

Latest local gate: 186 unit tests plus UAS, assurance, platform, validation, and
fidelity integration executables.

## Scaffold-level contracts

- JSBSim, OpenVSP, OpenMDAO, ROS 2/DDS, CARLA, PhysX, OpenUSD, Project AirSim,
  PX4/ArduPilot adapters
- WorldForge generation, DesignEvolve search, rare-event sampling,
  multi-fidelity scheduling, live digital twins, and learned models
- browser product interfaces

These contracts compile and have boundary tests; no linked external system or
validated frontier model is claimed.

## Next proof work

- public license
- independent atmosphere and dynamics cross-implementation comparisons
- linked JSBSim/OpenVSP adapter conformance runs
- full scenario-schema ingestion and canonical evidence-package export
- uncertainty propagation rather than status-only representation
- cross-target replay measurements
