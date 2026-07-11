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

- Operator-owned flight/ulog before Month-6 ops claim (public PX4 sample remains default)
- Real embedding backend for analogy (stub only; do not fake vectors)
- Serial HIL against live UART hardware (CLI wired; not required in verify)

## Live PX4 SITL (opt-in; never verify)

```sh
tools/px4_sitl_smoke.sh
# or, with docker already up on host network:
./zig-out/bin/strip-mavlink-sitl udp --host 127.0.0.1   # probes 13030/14280/14580/18570
```

MAVLink v2 framing in `src/interop/mavlink_v2.zig`. Echo selftest uses ports 28570/28571 (avoids PX4 GCS 18570).
