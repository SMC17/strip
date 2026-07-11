# Later product wedges

Date: 2026-07-11  
Status: **engines landed** — not operational qualification.

| Wedge | Surface | Honest status |
|-------|---------|---------------|
| Certification-delta | `strip-certification-delta` | Engine CLI emits delta JSON |
| Model credibility passport | `strip-model-passport` | Issuance CLI for known model ids |
| Physical HIL bench | `strip-hil-bench` | `selftest-unix` daemon path in verify; `serve/run --unix` and `--serial` |
| Flight evidence | `strip-flight-seal` + `STRIP_FLIGHT_PACKAGE` | Default telemetry is public PX4 ULog export (`px4-ulog-export.csv`); still `operational_qualification_claimed: false` |
| MAVLink / PX4 SITL | `strip-mavlink-sitl` + `tools/px4_sitl_smoke.sh` | Loopback + UDP echo in verify; **live MAVLink v2** to docker px4-sitl (`udp` probes 13030/14280/…) |
| Navigation capability | `schemas/navigation-capability.schema.json` | Doctrine map + schema |
| Dispatch decision evidence | `strip-dispatch decide` | Advisory engine; rails for unapproved weather / duty / pressure |
| WeatherNext client | `strip-weathernext` | WeatherNext Graph default; interim `--interim open-meteo`; WN2 deferred until out of open beta |
| Trajectory kernel | `strip-trajectory` + `docs/TRAJECTORY.md` | Live router; receipt→`verdict-attach`; workers/analogy/WM/HIL stream |

`operational_qualification_claimed` is forced `false` on all scaffold artifacts.
