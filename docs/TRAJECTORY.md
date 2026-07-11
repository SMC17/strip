# Strip trajectories (assurance agent OS)

Date: 2026-07-11  
Proof level: `integration-tested` (+ platform-plane live router when keys present)  
Operational qualification: **false**

## Live router (platform plane)

Keys (never committed):

- Google: `GOOGLE_API_KEY` / `GEMINI_API_KEY` / `~/.local/state/stax/google-api-key`
- OpenRouter: `OPENROUTER_API_KEY` / `~/.config/openrouter/key`

```sh
./zig-out/bin/strip-trajectory router status --intent research
./zig-out/bin/strip-trajectory router --live --intent ask "Reply with exactly: US76_OK"
```

`zig build verify` never calls these endpoints.

## Deepened surfaces

| Gap | Now |
|-----|-----|
| Router | Live OpenRouter + Gemini dispatch; offline fixture select in verify |
| Workers | Assignment JSONL persistence under `trajectory.evidence/` |
| Analogy | Ordered FAC adjacency bonus + recovery preference |
| World-model | 1-D ID loop + Strip rigid-body free-fall residual gate |
| HIL→JSONL | In-process + `--unix` daemon stream |

## Commands

```sh
./zig-out/bin/strip-trajectory frontier
./zig-out/bin/strip-trajectory hil-stream --unix --out trajectory.evidence
```
