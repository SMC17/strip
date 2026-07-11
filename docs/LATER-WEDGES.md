# Later product wedges

Date: 2026-07-11  
Status: **engines landed** — not operational qualification.

| Wedge | Surface | Honest status |
|-------|---------|---------------|
| Certification-delta | `strip-certification-delta` | Engine CLI emits delta JSON |
| Model credibility passport | `strip-model-passport` | Issuance CLI for known model ids |
| Physical HIL bench | `strip-hil-bench` | `selftest-unix` daemon path in verify; `serve/run --unix` and `--serial` |
| Flight evidence | `strip-flight-seal` + `STRIP_FLIGHT_PACKAGE` | Verify seals held-out package → `flight_test: passed`; campaign-10k without env stays `missing` |
| MAVLink / PX4 SITL | `strip-mavlink-sitl selftest` | HEARTBEAT loopback + fault inject; not live PX4 |
| Navigation capability | `schemas/navigation-capability.schema.json` | Doctrine map + schema |
| Dispatch decision evidence | `strip-dispatch decide` | Advisory engine; rails for unapproved weather / duty / pressure |
| WeatherNext client | `strip-weathernext` | Platform-plane fixture/status/live; **not** invoked from verify |
| Trajectory kernel | `strip-trajectory` + `docs/TRAJECTORY.md` | Typed actions, JSONL fold, claim-vs-evidence audit, duplicate-delivery idempotency |

`operational_qualification_claimed` is forced `false` on all scaffold artifacts.
