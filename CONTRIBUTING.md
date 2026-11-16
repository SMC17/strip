# Contributing to strip

Thank you for your interest in contributing to **strip**.

## Prerequisites

- [Zig](https://ziglang.org/) **0.16.0**

```sh
git clone https://github.com/SMC17/strip.git
cd strip
zig build verify
zig build
```

## Guidelines

- **One topic per PR** and link the relevant issue (`Closes #N`) when applicable.
- **Evidence first.** Include the exact command, commit, toolchain, and target machine for any validation or benchmark claim.
- **Keep diffs narrow.** Co-locate unit tests with the module you change and avoid modifying unrelated files.
- **Zig 0.16 conventions.** Prefer explicit error sets, allocator-aware APIs, and `defer` for resource cleanup.
- **Governance & security.** See [GOVERNANCE.md](GOVERNANCE.md) for promotion boundaries and [SECURITY.md](SECURITY.md) for reporting vulnerabilities.

## License

By contributing, you agree that your contributions are licensed under the [Apache License 2.0](LICENSE).
