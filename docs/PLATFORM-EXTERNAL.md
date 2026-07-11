# Platform external integrations

## Trust boundary

| Plane | Network | LLM (OpenRouter) | Authoritative |
|-------|---------|------------------|---------------|
| Simulation (`strip sim`) | **Forbidden** | **Forbidden** | Yes — deterministic manifest |
| Assurance (`strip assurance`) | Read-only ingest | Advisory only | Claims/evidence only |
| Platform (`strip lab`) | Allowed | Allowed | **Never** — produces candidates |

OpenRouter and any remote API belong **only** to the platform plane. Outputs are drafts until they pass schema validation, assurance review, and (where applicable) human sign-off.

## OpenRouter (planned)

**Use cases (non-authoritative):**

- Natural-language → structured campaign TOML draft
- Failure-cluster summarization for counterexample reports
- Test-card prose from flight-test foundry metrics
- Gap explanations in assurance reports

**Forbidden:**

- Setting simulation parameters without manifest
- Approving claims or waivers
- Modifying evidence graph directly
- Any call from `zig build verify`, proof/verification gates, or RK4 executive

**Wiring pattern:**

```
platform/openrouter/
├── client.zig          # HTTP via std or thin Python sidecar
├── prompts/            # Versioned, content-addressed prompt templates
├── schemas/            # Strict JSON outputs only
└── audit.zig           # Log every request/response hash + model id
```

Environment: `OPENROUTER_API_KEY` — platform jobs only; never in CI sim paths.

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

- **Next:** Month 9 — co-simulation clock, fault injection, replay evidence ingest

## OpenMDAO

- **Next:** Python adapter exposing Strip models as explicit components with evidence metadata export

## CI supply chain (target)

- GitHub Actions pinned to commit SHAs
- `jsonschema==<pin>` with hash
- OpenVSP deb SHA256 in workflow
- Run manifest records compiler, target, and dependency digests
