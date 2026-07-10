# Strip Status

Date: 2026-07-10

## Shipped slice

- Evidence metadata and context-of-use types
- Distinct SI quantity wrappers
- Spatial/time frame identifiers
- U.S. Standard Atmosphere troposphere model
- Evidence-bearing JSON CLI with out-of-envelope refusal

Proof level: `unit-tested`

Verification:

```sh
zig build test
zig build
./zig-out/bin/strip atmosphere 1000 preliminary_design
```

## Next slice

Implement WGS84 geodesy and typed ECEF/geodetic/NED transforms, including
round-trip property tests and explicit frame conversion APIs. This establishes
the coordinate contract required before flight dynamics.

## Open decisions

- public license
- canonical schema serialization and schema files
- content-addressed configuration identity
- uncertainty representation
- independent atmosphere comparison implementation
