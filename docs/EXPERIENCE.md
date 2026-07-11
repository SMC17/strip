# Sovereign Experience seed (Strip)

Date: 2026-07-11  
Status: **seed contracts** — not a shipped design system. Split target: `SMC17/sovereign-experience`.

## Why this lives here first

Portfolio UI must not be “same dark theme.” It must share **state, time, authority,
evidence, and interaction grammar** across Strip, Yard, zkdb/ztop, proof, inference,
and Mast — while each domain keeps its real instruments.

Substrate preference (portfolio-wide):

| Layer | Choice |
|-------|--------|
| App state / collab / streaming control | Phoenix LiveView (`sovereign_ui`) |
| Portable interactive islands | Lit web components |
| Tokens | DTCG JSON → Style Dictionary (+ Zig/Elixir/ANSI/WGSL exporters) |
| Dense analytical transport | Apache Arrow |
| Authoritative compute | Zig (+ WASM previews) |

Do **not** replace the LiveView control plane with a React SPA. Do **not** mix
React Aria + Radix + Base UI in one app.

## Workbench shell (shared)

```
Product · Project · Scenario · Run · Authority · Time · Environment
Navigator | Primary canvas | Inspector
Timeline · Replay · Logs · Terminal · Problems · Evidence · Agents
```

Universal verbs: Create → Configure → Run → Observe → Inspect → Compare →
Explain → Validate → Promote → Export → Replay.

Authority ladder: `proposal → candidate → evaluated → validated → accepted`
(or `rejected` / `refuted`).

## Visual language (precision industrial)

Replace neon/glass mockups with:

- Opaque surfaces, thin borders, one product accent
- Color for **state**, not decoration
- Monospace only for values / ids
- Units + timestamps always visible
- Shape+label status (not color alone): PROPOSAL / SIMULATED / ACCEPTED / STALE / REFUTED

## Engine map (default)

| Need | Engine |
|------|--------|
| Streaming grid | Perspective |
| Routine charts | ECharts |
| Flagship custom viz | D3 |
| Basemap | MapLibre |
| Dense geo layers | deck.gl |
| Weather rasters | WeatherLayers GL (when self-hosted) |
| Globe / orbit / terrain | CesiumJS |
| Scientific fields/meshes | VTK.js |
| Graphs | Cytoscape → Sigma at scale |
| Editors / terminals | CodeMirror / xterm.js |
| Docking | Dockview island |
| Game | raylib-zig (Gradient) — separate art direction |
| TUI | Vaxis from same tokens (Mast) |

## Seed artifacts in this repo

| Path | Role |
|------|------|
| `schemas/artifact-envelope.schema.json` | Typed value wrapper (authority, units, provenance) |
| `schemas/experience-tokens.schema.json` | Token-layer contract |
| `fixtures/experience/authority.tokens.json` | Authority color/symbol seed |
| `fixtures/experience/artifact-envelope.valid.json` | Golden envelope |

Flagship vertical slices (next): Yard box-barge margins, Strip UAS link-loss
replay, ztop temporal rewind, stax-proof claim lineage — extract shared components
only after **two** apps need them.
