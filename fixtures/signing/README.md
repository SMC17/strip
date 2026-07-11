# Strip CI / deployment attestation keys

## Development (committed)

Seed: `fixtures/signing/ci-seed.ed25519.hex`  
Public: `fixtures/signing/ci-public.ed25519.hex`

Used by default so `zig build verify` can sign and check evidence/campaign
bundles without secrets infrastructure.

## Production override

Set both:

```sh
export STRIP_SIGNING_SEED=<64-hex-seed>
export STRIP_SIGNING_PUBLIC_KEY=<64-hex-public>
```

`strip-evidence`, `strip-campaign`, and `strip-verify` honor these. The public
key must match the seed-derived keypair or verification fails.

This is still not an HSM. For organizational signing, inject the seed from a
secret store / KMS-backed agent and never commit production seeds.

