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

**Non-claim:** Strip-native Zig `strip.trajectory.receipt.v0` emitter still uses
a digest-hex attestation envelope. This directory does not prove Zig↔JS parity.
`operational_qualification_claimed`: false.
