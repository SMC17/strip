---
sidebar_position: 3
title: Architecture
---

# Architecture

Three planes on one evidence substrate. Simulation never talks to the network; platform orchestration is non-authoritative until assurance seals it.

```mermaid
flowchart TB
  subgraph Lab["Strip Lab — platform"]
    campaigns[Campaigns / reports]
    or[OpenRouter drafts — non-authoritative]
  end
  subgraph Assurance["Strip Assurance"]
    claims[Claims / hazards / reviews]
  end
  subgraph Sim["Strip Sim — deterministic"]
    exec[Executive + models]
    sensors[Sensors / runtime]
  end
  subgraph Substrate["Evidence substrate"]
    units[Units / frames / time]
    id[Execution identity]
    uq[UQ / validity domains]
    ser[Canonical serialization]
  end
  Lab --> Assurance
  Assurance --> Sim
  Sim --> Substrate
  Lab --> Substrate
```

## Product vs experimental

| Surface | Import path | Status |
|---------|-------------|--------|
| Atmosphere, dynamics, fixed-wing, validation, UAS, assurance | `strip.*` | Product / programme |
| Agent, AeroIR, WorldForge, twin, … | `strip.experimental.*` | Contracts only |

## External evidence producers

```mermaid
flowchart LR
  JSBSim --> Strip
  OpenVSP --> Strip
  FMI --> Strip
  PX4 --> Strip
  Strip --> Bundle[Signed evidence package]
```

Strip owns protocols, digests, disagreement reporting — not clones of those tools.
