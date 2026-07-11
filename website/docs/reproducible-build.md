---
sidebar_position: 6
title: Reproducible build
---

# Reproducible Linux build

Canonical pin table lives in the repo: [`docs/REPRODUCIBLE-BUILD.md`](https://github.com/SMC17/strip/blob/main/docs/REPRODUCIBLE-BUILD.md).

| Component | Pin |
|-----------|-----|
| Zig | `0.16.0` |
| `actions/checkout` | `34e114876b0b11c390a56381ad16ebd13914f8d5` |
| `mlugg/setup-zig` | `d1434d08867e3ee9daa34448df10607b98908d29` |
| jsonschema | `4.23.0` (wheel sha256 documented in repo) |
| OpenVSP deb | `sha256:53c02bca9ed3c14b1d2c62f5c1f4a0783a3de71d577a7f9e396fd022bc7bc262` |

## Docs site (this site)

From the Strip repo root (absolute path on this workstation: `/home/stax/sovereign-physics/strip`):

```sh
cd /home/stax/sovereign-physics/strip/website
npm ci
npm run build
npm start
```

## License

Apache-2.0 — [`LICENSE`](https://github.com/SMC17/strip/blob/main/LICENSE).
