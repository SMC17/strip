# Strip trajectories (assurance agent OS)

Date: 2026-07-11  
Proof level: `integration-tested` (+ platform-plane live router when keys present)  
Operational qualification: **false**

## Live router (platform plane)

Keys (never committed):

- Google: `GOOGLE_API_KEY` / `GEMINI_API_KEY` / `~/.local/state/stax/google-api-key`
- OpenRouter: `OPENROUTER_API_KEY` / `~/.config/openrouter/key`

```sh
./zig-out/bin/strip-trajectory router status --intent research
./zig-out/bin/strip-trajectory router --live --intent ask "Reply with exactly: US76_OK"
```

`zig build verify` never calls these endpoints.

## Deepened surfaces

| Gap | Now |
|-----|-----|
| Router | Live OpenRouter + Gemini dispatch; offline fixture select in verify |
| Workers | Assignment JSONL persistence under `trajectory.evidence/` |
| Analogy | Ordered FAC adjacency bonus + recovery preference; `EmbeddingLane` stub explicitly not wired (MAC/FAC authoritative) |
| World-model | 1-D ID loop + Strip rigid-body free-fall residual gate |
| HIL→JSONL | In-process + `--unix` daemon + `--serial DEVICE` (hardware optional; verify stays unix/in-process) |
| Flight seal | `--telemetry PATH` (default) and `--ulog PATH` → `tools/ulog_to_strip_csv.py` then seal |

## Commands

```sh
./zig-out/bin/strip-trajectory frontier
./zig-out/bin/strip-trajectory hil-stream --unix --out trajectory.evidence
./zig-out/bin/strip-trajectory hil-stream --serial /dev/ttyUSB0 --out trajectory.evidence
./zig-out/bin/strip-flight-seal build --out /tmp/strip-flight-seal --ulog fixtures/validation/flight-test/px4-sample-log-small.ulg
```

## Still blocked / operator-owned

- **Your** operator-owned flight/ulog (public Flight Review fixed-wing log is now default sealed evidence)
- Real embedding backend for analogy (stub only)
- Vertex WeatherNext EAP / Google Maps Weather OAuth (interim: Open-Meteo + NOAA/NWS)

## Public aircraft flight log

```sh
tools/fetch_public_flight_ulog.sh
./zig-out/bin/strip-flight-seal build --require-holdout
# or from cached .ulg:
./zig-out/bin/strip-flight-seal build --ulog ~/.cache/strip/flight-logs/px4-public-fixedwing-0316157c.ulg
```

Provenance: `fixtures/validation/flight-test/px4-public-fixedwing-export.provenance.json` (`public_aircraft_flight_log`).

## Serial / UART HIL

```sh
tools/hil_serial_pty_smoke.sh
./zig-out/bin/strip-hil-bench selftest-serial-pty
```

## Live PX4 SITL (opt-in; never verify)

```sh
tools/px4_sitl_smoke.sh
# or, with docker already up on host network:
./zig-out/bin/strip-mavlink-sitl udp --host 127.0.0.1   # probes 13030/14280/14580/18570
```

MAVLink v2 framing in `src/interop/mavlink_v2.zig`. Echo selftest uses ports 28570/28571 (avoids PX4 GCS 18570).
