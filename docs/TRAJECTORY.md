# Strip trajectories

Date: 2026-07-11  
Proof level: `integration-tested` (fixture fold + claim audit + duplicate-delivery idempotency)  
Operational qualification: **false**

## Strategic call

Do **not** contribute Cursor reverse-engineering as a product. Cursor’s agent OS
ideas (typed tool IR, event-sourced sessions, governance before execution,
claim-vs-evidence) map onto Strip’s existing assurance stack. Build the
aerospace-grade version here.

| Agent-OS concept | Strip surface |
|------------------|---------------|
| ToolCall IR | `strip.trajectory.action.Action` |
| Append-only trajectory | `strip.trajectory.store` + JSONL fixtures |
| Policy before execute | `policy_evaluated` events |
| Verification evidence | `verification_completed` |
| Reject unsupported claims | `claim_asserted` requires passed evidence refs |
| UI disposable / runtime durable | Trajectory fold is independent of any TUI |
| Fault inject | Duplicate `delivery_id` is idempotent |

## Commands

```sh
./zig-out/bin/strip-trajectory selftest
./zig-out/bin/strip-trajectory audit --path fixtures/trajectory/unsupported-claim.jsonl --expect-fail
```

## Honest limits

- Not a multi-model router, worker fabric, or Cursor protocol clone.
- Not analogical memory, counterfactual replay across models, or HIL yet.
- Fixtures are synthetic assurance narratives, not aircraft flight evidence.
