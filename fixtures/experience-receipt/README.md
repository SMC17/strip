# Experience-format receipt fixtures (AF wedge)

Mirrored from `SMC17/sovereign-experience` `fixtures/strip/` for Strip CI.

| File | Role |
|------|------|
| `uas-receipt.json` | Field-presence-only fixture |
| `uas-receipt-ed25519.json` | Signed Experience wire format |
| `ed25519-dev-key.json` | **DEV ONLY** key material — not production custody |
| `uas-trajectory.jsonl` | Trajectory events referenced by receipts |

`tools/experience-receipt-verify/` runs Node verify via the Experience
`@sovereign/assurance` receipt port (vendored `lib/receipt.js`).

Set `ZIG_RECEIPT=/path/to/receipt.json` to also verify a Zig-emitted trajectory
receipt with the same JS verifier.

**Zig emitter:** `strip.trajectory.receipt.v0` from `src/trajectory/receipt.zig`
now emits Experience-compatible wire format (sorted-key body → SHA-256 → Ed25519
over raw 32-byte hash). Dual digest-hex envelope is retired for trajectory
receipts; campaign/evidence may still use `Signature.formatJson` (digest-hex
message attestation).

`operational_qualification_claimed`: false. No HSM / OQ claim.
