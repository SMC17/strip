# Strip Status

Date: 2026-07-10

## Executable surface

- evidence kernel, canonical JSON subset, strict schemas, and public-use policy
- typed math, WGS84 transforms, simulation time, RNG, identity, and replay
- atmosphere, mass properties, 6-DOF, aerodynamics, controls, and sensors
- deterministic scheduler, Monte Carlo aggregation, and integrated UAS fixture
- assurance graph with weakest-link, stale, missing, and cycle checks
- constrained agent permissions and replay structures
- product/frontier inventory and explicit unavailable adapter catalog

Proof level: `unit-tested`

Verification:

```sh
zig build verify
zig build test -Doptimize=ReleaseSafe
./zig-out/bin/strip atmosphere 1000 preliminary_design
```

Latest local gate: 76 unit tests plus UAS, assurance, and platform integration
executables.

## Scaffold-level contracts

- JSBSim, OpenVSP, OpenMDAO, FMI, ROS 2/DDS, HLA/DIS, MAVLink, and public-data
  adapters
- WorldForge generation, DesignEvolve search, rare-event sampling,
  multi-fidelity scheduling, live digital twins, and learned models
- browser product interfaces

These contracts compile and have boundary tests; no linked external system or
validated frontier model is claimed.

## Next proof work

- public license
- independent atmosphere comparison implementation
- independent geodesy and dynamics comparisons
- full scenario-schema ingestion and canonical evidence-package export
- uncertainty propagation rather than status-only representation
- cross-target replay measurements
