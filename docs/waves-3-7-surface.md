# Waves 3–7 surface

The root build exports these modules and verifies executable foundations for
scenario ordering, Monte Carlo aggregation, UAS contingency decisions,
assurance dependencies, and permissioned agent replay.

The `aeroir`, `worldforge`, `design_evolve`, `rare_event`, `multifidelity`,
`twin`, and `adapters` packages are typed research or integration contracts.
They do not claim an external solver, generator, optimizer, calibrated rare
event method, physical twin, or third-party connection exists.

`public_defense` is limited to generic anomaly assessment and bounded resilience
responses. It contains no targeting, weapons-effects, or operational-control
logic.

## UAS fixture

`examples/uas_contingencies.csv` records human-readable workflow cases. The
standalone app emits the built-in nominal, lost-link, and simultaneous
breach/fault cases:

```sh
zig build run-uas
zig build run-assurance
zig build run-platform
```

The policy is a simulation fixture, not an operational flight controller. Its
precedence is geofence breach, propulsion fault, navigation fault, predicted
geofence breach, then link state.

The product inventory reports adapter and frontier contracts separately from
authoritative executable components. An unavailable adapter fails closed rather
than silently substituting a local implementation.
