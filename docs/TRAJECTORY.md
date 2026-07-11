# Strip trajectories (assurance agent OS)

Date: 2026-07-11  
Proof level: `integration-tested`  
Operational qualification: **false**

## Strategic call

Do **not** contribute Cursor reverse-engineering. Cursor’s agent-OS pattern maps
onto Strip’s assurance stack. This module is the clean-room aerospace substrate.

## Architecture map (frontier pack)

| Agent-OS layer | Strip surface | Status |
|----------------|---------------|--------|
| ToolCall / agent IR | `trajectory.action` + `trajectory.aerospace` | typed + control-law contract |
| Append-only trajectory | `trajectory.store` + JSONL | fold + idempotent delivery |
| Policy before execute | `policy_evaluated` | enforced in fixtures |
| Claim vs evidence | `claim_asserted` → passed verifications | reject unsupported |
| Causal provenance | `trajectory.causal` | support/contradict edges |
| Counterfactual replay | `trajectory.counterfactual` | policy-denial branch |
| Fault laboratory | `trajectory.fault_lab` | 4 scenarios in verify |
| Assurance receipt | `trajectory.receipt` (Ed25519) | sealed JSON |
| Memory classes | `trajectory.memory` | retention policy scaffold |
| Hierarchical tasks | `trajectory.scheduler` | typed deps + ready set |
| Evidence binding | `programs/reference-uas.toml` `trajectory=` | digest in evidence bundle |
| UI disposable | fold/receipt independent of TUI | yes |

## Commands

```sh
./zig-out/bin/strip-trajectory selftest
./zig-out/bin/strip-trajectory audit --path fixtures/trajectory/unsupported-claim.jsonl --expect-fail
./zig-out/bin/strip-trajectory frontier
./zig-out/bin/strip-trajectory receipt --out trajectory.evidence
./zig-out/bin/strip-evidence build programs/reference-uas.toml
```

## What is still not claimed

- Live multi-model router / Bedrock / local provider observatory
- Worker fabric / Temporal / private cloud workers
- Analogical MAC/FAC trajectory memory
- World-model predict-then-execute loop
- Cursor protocol clone or Runtime Atlas
- Aircraft / FSTD / operational qualification

Next concrete wedges: counterfactual across campaign seeds; bind receipt into
`stax-experiment` verdict evidence automatically; HIL event streaming into JSONL.
