# Comparator tolerances

Date: 2026-07-11

Every validation case declares **per-variable** acceptance metrics with an explicit rationale. Global `acceptance` remains only as a fallback for variables without a metric row (legacy fixtures / shim backends).

## Rule

```
tolerance(variable) = max(abs_tol, rel_tol * |reference|)
```

A comparison **passes** iff `|observed − reference| ≤ tolerance(variable)`.

## Schema

`strip.validation-case.v1` requires `metric_acceptance[]`:

| Field | Meaning |
|-------|---------|
| `variable` | Must match comparison / sample variable names |
| `unit` | SI or dimensionless `1` |
| `absolute_tolerance` | Floor error allowed |
| `relative_tolerance` | Fraction of `|reference|` |
| `rationale` | Why these numbers are honest for this gate |

## Published JSBSim / US76 metrics

| Variable | abs | rel | Rationale |
|----------|-----|-----|-----------|
| `temperature_k` | 0.5 K | 1e-4 | US76 table resolution; cross-implementation atmosphere gate |
| `pressure_pa` | 50 Pa | 1e-4 | Hectopascal-scale tabular rounding at layer boundaries |
| `density_kg_m3` | 0.02 | 1e-3 | Derived from T and P; independent ideal-gas check |
| `speed_of_sound_mps` | 0.5 | 1e-4 | √(γRT); small numerical spread expected |

## Coefficient parity (shared linear model)

| Variable | abs | rel | Rationale |
|----------|-----|-----|-----------|
| `cx`…`cn` | 1e-4 | 1e-3 | Shared linear model coefficient parity (not F-16 aero tables) |

## Fixed-wing integrate (JSBSim F-16 host)

| Variable | abs | rel | Rationale |
|----------|-----|-----|-----------|
| `altitude_m` | 5.0 | 0.02 | Short integrate; host vehicle, not Strip native aero |
| `vt_mps` | 2.0 | 0.02 | Airspeed integration drift on published fixture |
| `alpha_deg` / `theta_deg` | 0.5 | 0.02 | Angle states; fixture-scale acceptance |
| `q_radps` | 0.05 | 0.05 | Pitch rate |
| `ax_mps2` / `az_mps2` | 1.0 | 0.05 | Body accel from host |
| `qdot_radps2` | 0.1 | 0.05 | Angular accel |

## Synthetic perturbation fixture

Deliberate failure fixture keeps tight tolerances (`abs=0.001`, `rel=0.01` on `mach`) so a one-count perturbation is guaranteed to fail. It is **not** physical validation evidence.

## Source

Executable definitions: `src/adapters/jsbsim.zig` (`crossImplementationMetrics`, `coefficientMetrics`, `fixedWingIntegrateMetrics`) and case JSON under `fixtures/validation/`.
