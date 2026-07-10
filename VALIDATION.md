# Validation

## Current proof level

`unit-tested`

The atmosphere implementation has an `analytical` model-manifest label for the
implemented hydrostatic/lapse-rate equations. Fixed-wing and multirotor modules
are bounded low-order models with explicit synthetic-vs-transcribed labeling in
vehicle manifests. This does not mean the project as a whole is analytically
validated, flight-qualified, or cross-platform deterministic.

## Evidence

Run:

```sh
zig build verify
zig build test -Doptimize=ReleaseSafe
./zig-out/bin/strip atmosphere 1000 preliminary_design
./zig-out/bin/strip-validation
./zig-out/bin/strip-fidelity
./zig-out/bin/strip-proof-gates
```

Checks currently cover:

- component-wise proof inheritance and public-use refusal
- canonical JSON ordering/escaping and content digest stability
- non-finite altitude rejection and reference-frame tag retention
- US76 sea-level and 11,000 m pressure; full 86 km layer envelope
- Dryden/von Kármán spectral shapes and replayable forming filters
- WGS84 cardinal points, round trips, and ECEF/NED inverse transforms
- coupled RK4 with per-stage load callbacks, state validation, and diagnostics
- Earth rotation/transport and latitude/height gravity models
- fixed-wing airdata, coefficient interpolation, propulsion, trim, and maneuvers
- multirotor thrust/torque, motor lag, allocation, control, and battery accounting
- deterministic scheduler catch-up, scene layering, collision/CCD, and sensor timing
- validation schemas, 18-source manifest, coverage matrix, and perturbed comparator failure
- flight-test telemetry, regression, residuals, maneuver cards, and sealed evidence manifests
- typed interop contracts (FMI 3.0, MAVLink, HLA/DIS) with explicit unavailability
- JSBSim out-of-process comparator via `JSBSIM_CMD` (`tools/jsbsim_cmd.sh` + pip `jsbsim`) or development shim; evidence tier reported explicitly
- OpenVSP pinned geometry digest conformance (v3.42.0) and analytic tessellation mesh digest/area/count
- cross-target RK4 replay fingerprints with `pending` baselines for aarch64/linux and macOS CI matrix legs
- uncertainty: analytic affine propagation, Monte Carlo calibration, and flight-data fusion with quality gates
- deterministic UAS wind/link-loss integration and assurance weakest-link behavior

Primary grounding sources are cataloged in `sources/primary-sources.json` with
content-addressed locator digests. Digest scope is `locator_record` unless
otherwise stated; catalog presence is not model-validation evidence.

## Validity envelope

- atmosphere: geopotential altitude 0 through 86 km (homogeneous dry-air hydrostatic model)
- coupled dynamics: rigid body with state-dependent loads reevaluated each RK4 stage
- fixed-wing: bounded coefficient tables; NASA TP-1538 manifest is synthetic scaffold only
- multirotor: static-coefficient rotors with motor lag; UIUC manifest distinguishes synthetic data
- UAS integration: local Cartesian fixture with hover thrust and constant wind (low fidelity)
- runtime: deterministic for fixed executable and recorded inputs; cross-platform FP not claimed
- public APIs: education, research, preliminary design, and simulation training

## Not measured

- agreement against independent vehicle-dynamics implementations (JSBSim fixed-wing, OpenVSP CAD export)
- numerical reproducibility across architectures (aarch64/macos replay baselines still pending)
- linked external adapters or learned-model performance
- operational, certification, accreditation, real-time, or hardware use
- flight, HIL, or FAA Part 60 qualification

## Error lens

- Type I risk: breadth may be mistaken for fidelity. Most adapter and frontier modules
  are typed contracts; the executable UAS workflow remains deliberately low fidelity.
  Product-wide validation is not claimed.
- Type II risk: embedded tests may miss shared formula errors and realistic coupled
  failures. Independent implementations, published fixtures, and hardware/flight
  evidence remain required.
