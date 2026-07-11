# Platform external integrations

## Trust boundary

| Plane | Network | LLM (OpenRouter) | Authoritative |
|-------|---------|------------------|---------------|
| Simulation (`strip sim`) | **Forbidden** | **Forbidden** | Yes — deterministic manifest |
| Assurance (`strip assurance`) | Read-only ingest | Advisory only | Claims/evidence only |
| Platform (`strip lab`) | Allowed | Allowed | **Never** — produces candidates |

OpenRouter and any remote API belong **only** to the platform plane. Outputs are drafts until they pass schema validation, assurance review, and (where applicable) human sign-off.

## OpenRouter (platform only)

- **Client:** `src/platform/openrouter.zig`
- **Key:** `OPENROUTER_API_KEY` or `~/.config/openrouter/key` (mode 600)
- **CLI:** `strip-trajectory router status| --live`
- **Forbidden:** any call from `zig build verify`

## Google / DeepMind (platform only)

- **Docs:** [domain/GOOGLE-DEEPMIND.md](domain/GOOGLE-DEEPMIND.md)
- **CLI:** `strip-google catalog|gemini …` and `strip-trajectory router --live` (Gemini path)
- **Gemini live:** `GEMINI_API_KEY` / `GOOGLE_API_KEY` or `~/.local/state/stax/google-api-key`
- **WeatherNext:** still `strip-weathernext` (Vertex/endpoint — not the Gemini key)
- **Verify:** offline `catalog` + `gemini fixture` only; no live network calls

## WeatherNext / WeatherLab (platform only)

- **CLI:** `strip-weathernext status|fixture|fetch --live [--interim open-meteo]`
- **Docs:** [domain/WEATHER-EXTERNAL.md](domain/WEATHER-EXTERNAL.md)
- **Default model family:** WeatherNext Graph (WN1-class) until WN2 leaves open beta/EAP
- **Source id:** `weathernext-2` remains bibliographic; fixture model id is `weathernext-graph`
- **Live:** `STRIP_WEATHERNEXT_ENDPOINT` or interim Open-Meteo via `--interim open-meteo`
- **Forbidden:** Simulation truth; OpsSpec weather without operator approval; **not run from `zig build verify`**

## Dispatch decision engine (advisory)

- **CLI:** `strip-dispatch decide ...`
- **Rails:** unapproved AI weather → forced no-go; duty-near-limit → no-go; owner pressure + risk → escalate/no-go
- **Always:** `operational_qualification_claimed: false`

## HIL daemon

- **CLI:** `strip-hil-bench local|selftest-unix|serve|run` with `--unix` or `--serial`
- **Verify:** runs `selftest-unix` (child serve + client progression)

## Aviation domain map (bibliography)

- **Index:** [domain/README.md](domain/README.md)
- **Navigation / AIM / GNSS-PBN:** [domain/NAVIGATION.md](domain/NAVIGATION.md)
- **Airspace / ZJX:** [domain/AIRSPACE.md](domain/AIRSPACE.md)
- **Dispatch gaps Part 91/135/121:** [domain/DISPATCH-OPS.md](domain/DISPATCH-OPS.md)
- **Scaffolds:** `schemas/navigation-capability.schema.json`, `schemas/dispatch-decision-evidence.schema.json`

## JSBSim

- **Today:** `JSBSIM_CMD=tools/jsbsim_cmd.sh` subprocess protocol
- **Role:** Cross-implementation comparator, not physical truth
- **Next:** Per-variable campaigns, layer-boundary grid, independent density referent

## OpenVSP

- **Today:** `vsp -script tools/openvsp_box_wing.vspscript` on ubuntu-24.04 CI
- **Role:** Export smoke + structural mesh bounds — **not** geometry identity (see P0.2 in ROADMAP)
- **Next:** Script digest pin, invocation audit, landmark geometry checks

## FMI 3.0

- **Today:** Typed contract in `src/interop/fmi.zig`
- **Next:** Import round-trip, state serialization tests, reference FMU execution

## PX4 / ArduPilot SITL

- **Today:** `strip-mavlink-sitl selftest` (loopback + localhost UDP echo); `udp --host/--port` for live peer
- **Next:** Persistent live `px4-sitl` session + MAVLink v2 when binary present

## Flight evidence

- **Today:** `strip-flight-seal` defaults to `px4-ulog-export.csv` from public PX4 ULog (`tools/ulog_to_strip_csv.py`)
- **Next:** Operator-owned flight/ulog before Month-6 operational claim

## OpenMDAO

- **Next:** Python adapter exposing Strip models as explicit components with evidence metadata export

## CI supply chain (target)

- GitHub Actions pinned to commit SHAs
- `jsonschema==<pin>` with hash
- OpenVSP deb SHA256 in workflow
- Run manifest records compiler, target, and dependency digests
