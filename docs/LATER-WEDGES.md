# Later product wedges

Date: 2026-07-11  
Status: **engines landed** — not operational qualification.

| Wedge | Surface | Honest status |
|-------|---------|---------------|
| Certification-delta | `strip-certification-delta` | Engine CLI emits delta JSON |
| Model credibility passport | `strip-model-passport` | Issuance CLI for known model ids |
| Flight evidence | `strip-flight-seal` + `STRIP_FLIGHT_PACKAGE` | Default = public aircraft Flight Review fixed-wing ULog export; still `operational_qualification_claimed: false` |
| Physical HIL bench | `strip-hil-bench` | unix + **serial PTY** (`selftest-serial-pty` / `tools/hil_serial_pty_smoke.sh`) |
| WeatherNext client | `strip-weathernext` | Graph default; interim `--interim open-meteo\|nws`; Vertex WN2 still EAP |
| MAVLink / PX4 SITL | `strip-mavlink-sitl` + `tools/px4_sitl_smoke.sh` | Loopback + UDP echo in verify; **live MAVLink v2** to docker px4-sitl (`udp` probes 13030/14280/…) |
| Navigation capability | `schemas/navigation-capability.schema.json` | Doctrine map + schema |
| Dispatch decision evidence | `strip-dispatch decide` | Advisory engine; rails for unapproved weather / duty / pressure |
| Trajectory kernel | `strip-trajectory` + `docs/TRAJECTORY.md` | Live router; receipt→`verdict-attach`; workers/analogy/WM/HIL stream |

`operational_qualification_claimed` is forced `false` on all scaffold artifacts.
