# Strip trajectories (assurance agent OS)

Date: 2026-07-11  
Proof level: `integration-tested`  
Operational qualification: **false**

## Strategic call

Clean-room aerospace substrate. Not a Cursor protocol clone.

## Architecture map

| Layer | Surface | Honest limit |
|-------|---------|--------------|
| ToolCall IR | `action` + `aerospace` | contracts, not autopilot |
| Event fold / claims | `store` + JSONL | fixture + HIL-stream narratives |
| Counterfactual | `counterfactual` | policy-denial branch |
| Causal provenance | `causal` | support/contradict edges |
| Fault lab | `fault_lab` | 4 scenarios |
| Receipt | `receipt` Ed25519 | sealed JSON |
| Memory classes | `memory` | retention policy only |
| Scheduler | `scheduler` | typed deps |
| **Multi-model router** | `router` | fixture registry + env probes; **no live API calls in verify** |
| **Worker fabric** | `workers` | in-process pools/labels/single-use |
| **Analogical memory** | `analogy` | MAC/FAC-style feature overlap, not embeddings |
| **World-model loop** | `world_model` | 1-D toy plant predict/execute/residual |
| **HIL → JSONL** | `hil_stream` | in-process `physical_bench_protocol` → foldable events |
| Evidence binding | `programs/reference-uas.toml` | trajectory digest |

## Commands

```sh
./zig-out/bin/strip-trajectory frontier
./zig-out/bin/strip-trajectory hil-stream --out trajectory.evidence
./zig-out/bin/strip-trajectory receipt --out trajectory.evidence
```

## Still not claimed

- Hosted model inference from verify
- Distributed/K8s workers or Temporal durability
- Embedding / neural analogy
- Full 6-DOF digital twin as world model
- Serial/UART HIL device streaming
