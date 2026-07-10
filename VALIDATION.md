# Validation

## Current proof level

`unit-tested`

The atmosphere implementation also has an `analytical` model-manifest label:
it directly evaluates the hydrostatic/lapse-rate equations and is checked at
two tabulated boundary conditions. This does not mean the project as a whole is
analytically validated.

## Evidence

Run:

```sh
zig build verify
zig build test -Doptimize=ReleaseSafe
./zig-out/bin/strip atmosphere 1000 preliminary_design
./zig-out/bin/strip atmosphere 12000 research
```

Checks currently cover:

- component-wise proof inheritance and public-use refusal
- canonical JSON ordering/escaping and content digest stability
- non-finite altitude rejection
- reference-frame tag retention
- standard sea-level temperature, pressure, density, and speed of sound
- 11,000 m pressure within 1 Pa of 22,632 Pa
- structured refusal above the implemented altitude envelope
- WGS84 cardinal points, round trips, and ECEF/NED inverse transforms
- deterministic clocks, event ordering, named RNG streams, and replay identities
- positive-definite inertia, constant-acceleration 6-DOF motion, and quaternion norm
- bounded aerodynamic interpolation, actuator/PID, IMU, and GNSS behavior
- deterministic UAS wind/link-loss integration and scenario identity
- assurance weakest-link, stale, missing, and cyclic dependency behavior
- AI permission denial, runtime recovery selection, and explicit adapter unavailability

The model constants and equations are grounded in *U.S. Standard Atmosphere,
1976*, NASA-TM-X-74335 / NOAA-S/T-76-1562:
https://ntrs.nasa.gov/citations/19770009539

## Validity envelope

- atmosphere: geopotential altitude 0 through 11,000 m, dry ideal gas,
  constant tropospheric lapse rate
- UAS integration: local Cartesian, fixed mass/inertia, constant wind force,
  hover thrust, simplified link/navigation/geofence states
- dynamics: rigid body with constant wrench over each fixed RK4 step
- public APIs: education, research, preliminary design, and simulation training

## Not measured

- agreement against an independent implementation
- behavior above 11,000 m
- full atmospheric variability, terrain, traffic, communications propagation,
  rotor/propeller aerodynamics, battery/energy, or structural dynamics
- numerical reproducibility across architectures
- linked external adapters or learned-model performance
- uncertainty propagation/calibration
- operational, certification, accreditation, real-time, or hardware use

## Error lens

- Type I risk: breadth may be mistaken for fidelity. Most frontier and adapter
  modules are typed contracts, while the executable UAS workflow is deliberately
  low fidelity. Product-wide validation is not claimed.
- Type II risk: embedded tests may miss shared formula errors and realistic
  coupled failures. Independent implementations, published fixtures, and
  hardware/flight evidence remain required.
