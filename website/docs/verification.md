---
sidebar_position: 4
title: Verification
---

# Verification

`zig build verify` is the local credibility compiler. CI adds multi-arch replay pins, real OpenVSP export, and a 10k campaign job.

```mermaid
flowchart TD
  fmt[zig fmt] --> unit[Unit tests]
  unit --> gates[strip-verification-gates]
  gates --> jsbsim[JSBSim atmosphere / fixed-wing / coeffs]
  gates --> openvsp[OpenVSP digest + export]
  gates --> replay[Replay matrix]
  gates --> uq[Uncertainty analytic / MC]
  gates --> flight[Flight evidence ladder]
  flight --> sil[SIL passed]
  flight --> hil[HIL: synthetic io_loopback today]
  flight --> ft[flight_test: missing until sealed package]
```

## Authoritative outputs

Every `NumericalResult(T)` carries `execution_identity` (`model_id`, `model_version`, optional `content_sha256` / `seed`).

Evidence and campaign manifests include:

```json
"execution_identity": {
  "content_sha256": "sha256:…",
  "seed": 42,
  "campaign_id": "reference-uas-contingency"
}
```

## Schemas

| Schema | Fixture |
|--------|---------|
| `strip.model-package.v1` | `fixtures/schemas/model-package.*.json` |
| `strip.run-manifest.v1` | `fixtures/schemas/run-manifest.*.json` |

## Honest limits

- Signing: Ed25519 CI key / env override — not HSM
- HIL: synthetic loopback, not a physical bench
- Flight: intentionally `missing`
