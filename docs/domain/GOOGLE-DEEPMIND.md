# Google / DeepMind platform map

Date: 2026-07-11  
Plane: **platform only** — never simulation truth, never OpsSpec weather, never ATC/dispatch authority.

## How to get an API key (Gemini family)

1. Open [Google AI Studio API keys](https://aistudio.google.com/apikey)
2. Sign in with your Google account and accept terms
3. Click **Create API key** (new keys are auth keys)
4. Export it for Strip platform CLIs **or** write it to the private workstation file (never commit):

```sh
# option A — env
export GEMINI_API_KEY="your-key"

# option B — private file (mode 600)
mkdir -p ~/.local/state/stax
chmod 700 ~/.local/state/stax
# printf '%s\n' 'your-key' > ~/.local/state/stax/google-api-key && chmod 600 ~/.local/state/stax/google-api-key

./zig-out/bin/strip-google gemini status
./zig-out/bin/strip-google gemini --live "Summarize RNAV vs RNP in one sentence"
./zig-out/bin/strip-dispatch brief --live --scenario "TEB-BOS marginal ceilings"
```

Default live model: **`gemini-3.5-flash`** (gemini-2.0-flash often returns free-tier quota 0 on new keys).


**WeatherNext is different:** it is not the Gemini API key. Live WeatherNext is Vertex AI / Model Garden (often Early Access) or a custom HTTP endpoint you configure as `STRIP_WEATHERNEXT_ENDPOINT` (+ optional `STRIP_WEATHERNEXT_TOKEN`). See [WEATHER-EXTERNAL.md](WEATHER-EXTERNAL.md).

## What “real device” meant (HIL serial)

Unix-socket HIL is already proven in CI (`strip-hil-bench selftest-unix`).

`--serial /dev/ttyUSB0` (or similar) talks the same SHIL frames over a **serial port file**. That needs an actual UART/USB-serial adapter or flight-controller link plugged into the machine. Without hardware, use `--unix` (or `selftest-unix`). Serial is API-ready; it is not a missing software feature.

## Product → Strip surface

| Product | Access | Strip today |
|---------|--------|-------------|
| Gemini / Omni / Audio | AI Studio API key | `strip-google gemini` |
| Nano Banana | catalog alias | map to published model id with `--model` |
| Gemma | open weights | catalog only (no bundled local runtime in verify) |
| Genie / Lyria / Veo | research / Vertex | catalog |
| Gemini Robotics | research | catalog (not Strip HIL) |
| WeatherNext | Vertex EAP / endpoint | `strip-weathernext` |
| AlphaFold / AlphaGenome / AlphaEarth / AlphaEvolve | science portals | catalog |

Full machine-readable list: `strip-google catalog`.

## Trust rails

- `authoritative: false`
- `operational_qualification_claimed: false`
- Never called from `zig build verify` live paths (catalog + gemini fixture may smoke offline)
