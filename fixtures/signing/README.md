# Strip CI attestation key (development only)

Seed: `fixtures/signing/ci-seed.ed25519.hex`  
Public: `fixtures/signing/ci-public.ed25519.hex`

This keypair is committed so `zig build verify` can produce and check Ed25519
signatures on evidence/campaign bundle digests without secrets infrastructure.

It is **not** a production organizational signing key. Rotate by regenerating
the seed, updating the public fixture, and bumping signature schema consumers.
