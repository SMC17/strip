# Reproducible Linux build

Date: 2026-07-11  
Host target: `x86_64-linux` (CI: `ubuntu-latest` / `ubuntu-24.04`)

## Pinned toolchain

| Component | Pin |
|-----------|-----|
| Zig | `0.16.0` (`mlugg/setup-zig@d1434d08867e3ee9daa34448df10607b98908d29`) |
| JSBSim (Python) | `jsbsim==1.3.1` |
| jsonschema | `4.23.0` (`sha256:fbadb6f8b144a8f8cf9f0b89ba94501d143e50411a1278633f56a7acf7fd5566`) |
| OpenVSP deb | `OpenVSP-3.42.0-Ubuntu-24.04_amd64.deb` (`sha256:53c02bca9ed3c14b1d2c62f5c1f4a0783a3de71d577a7f9e396fd022bc7bc262`) |

## Minimal verify

```sh
git clone https://github.com/SMC17/strip.git
cd strip
# Install Zig 0.16.0 from https://ziglang.org/download/
python3 -m venv .venv
.venv/bin/pip install --disable-pip-version-check jsbsim==1.3.1
export PATH="$(pwd)/.venv/bin:$PATH"
export JSBSIM_CMD=tools/jsbsim_cmd.sh
zig build verify
```

## Real OpenVSP export (optional)

```sh
# After installing the pinned OpenVSP 3.42.0 deb and verifying its SHA-256:
export OPENSP_CMD="$(command -v vsp)"
export OPENSP_RUNTIME_VERSION=3.42.0
export STRIP_REQUIRE_OPENSP_CMD=1
# Export once, then gate against the same STL (deterministic digest pin):
echo '{"schema":"strip.openvsp-export-protocol.v0","output_path":"openvsp-smoke.stl"}' \
  | python3 tools/openvsp_export.py export
./zig-out/bin/strip-mesh-digest openvsp-smoke.stl
STRIP_OPENVSP_STL=openvsp-smoke.stl ./zig-out/bin/strip-verification-gates
```

## Docs site

```sh
cd website
npm ci
npm run build
npm start   # local preview
```

## Evidence / campaign

```sh
./zig-out/bin/strip-evidence build programs/reference-uas.toml
STRIP_CAMPAIGN_RUN_ALL=1 ./zig-out/bin/strip-campaign run campaigns/reference-uas-contingency.toml
```

Outputs land in `program.evidence/` and `campaign.evidence/` with Ed25519 attestation under the CI development key (override with `STRIP_SIGNING_SEED` / `STRIP_SIGNING_PUBLIC_KEY`).
