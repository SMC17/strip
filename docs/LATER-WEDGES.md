# Later product wedges

Date: 2026-07-11  
Status: **engines + scaffolds** — not operational qualification.

| Wedge | Surface | Honest status |
|-------|---------|---------------|
| Certification-delta | `strip-certification-delta` + `schemas/certification-delta.schema.json` | Engine CLI emits delta JSON; not a certification claim |
| Model credibility passport | `strip-model-passport` + `schemas/model-passport.schema.json` | Issuance CLI for known model ids; C vector scaffold |
| Physical HIL bench | `strip-hil-bench` + `src/flight_test/hil_bench.zig` | Framed `SHIL` protocol path (`physical_bench_protocol`); in-process byte-stream today — not a serial/Unix-socket daemon |
| Flight evidence | `strip-flight-seal` + `STRIP_FLIGHT_PACKAGE` | Sealed package enables `flight_test: passed` when env points at verified package; default CI remains `missing` |
| Navigation capability | `schemas/navigation-capability.schema.json` | Doctrine map only; see [domain/NAVIGATION.md](domain/NAVIGATION.md) |
| Dispatch decision evidence | `schemas/dispatch-decision-evidence.schema.json` | Market-gap map only; see [domain/DISPATCH-OPS.md](domain/DISPATCH-OPS.md) |
| WeatherNext client | — | Documented platform candidate; no live client in verify |

`operational_qualification_claimed` is forced `false` on all scaffold artifacts.
