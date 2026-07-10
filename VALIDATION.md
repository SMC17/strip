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
zig build test
zig build
./zig-out/bin/strip atmosphere 1000 preliminary_design
./zig-out/bin/strip atmosphere 12000 research
```

Checks currently cover:

- non-finite altitude rejection
- reference-frame tag retention
- standard sea-level temperature, pressure, density, and speed of sound
- 11,000 m pressure within 1 Pa of 22,632 Pa
- structured refusal above the implemented altitude envelope

The model constants and equations are grounded in *U.S. Standard Atmosphere,
1976*, NASA-TM-X-74335 / NOAA-S/T-76-1562:
https://ntrs.nasa.gov/citations/19770009539

## Validity envelope

- geopotential altitude: 0 through 11,000 m, inclusive
- dry ideal gas
- constant tropospheric lapse rate
- no humidity, weather variability, turbulence, or uncertainty model

## Not measured

- agreement against an independent implementation
- behavior above 11,000 m
- geometric-to-geopotential altitude conversion
- numerical reproducibility across architectures and optimization modes
- operational, certification, accreditation, real-time, or hardware use

## Error lens

- Type I risk: a user may mistake an analytical atmosphere slice for a
  validated aerospace platform. The CLI exposes the narrow envelope and the
  project makes no operational claim.
- Type II risk: boundary-value tests may miss interior formula or constant
  errors. The next proof step is cross-implementation comparison against an
  independent U.S. Standard Atmosphere implementation over a generated grid.
