# Later product wedges

Date: 2026-07-11  
Status: **engines landed** — not operational qualification.

| Wedge | Surface | Honest status |
|-------|---------|---------------|
| Certification-delta | `strip-certification-delta` | Engine CLI emits delta JSON |
| Model credibility passport | `strip-model-passport` | Issuance CLI for known model ids |
| Physical HIL bench | `strip-hil-bench` | `selftest-unix` daemon path in verify; `serve/run --unix` and `--serial` |
| Flight evidence | `strip-flight-seal` + `STRIP_FLIGHT_PACKAGE` | Sealed package optional; default CI `flight_test: missing` |
| Navigation capability | `schemas/navigation-capability.schema.json` | Doctrine map + schema |
| Dispatch decision evidence | `strip-dispatch decide` | Advisory engine; rails for unapproved weather / duty / pressure |
| WeatherNext client | `strip-weathernext` | Platform-plane fixture/status/live; **not** invoked from verify |

`operational_qualification_claimed` is forced `false` on all scaffold artifacts.
