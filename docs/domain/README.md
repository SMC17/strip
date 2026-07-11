# Aviation domain map (non-authoritative)

Date: 2026-07-11  
Status: **domain bibliography + ops map** — not operational qualification.

This tree captures navigation, weather, airspace, and dispatch context for Strip’s
platform and assurance planes. Nothing here authorizes flight, dispatch release,
or ATC decisions.

| Doc | Scope |
|-----|--------|
| [NAVIGATION.md](NAVIGATION.md) | GNSS / PBN / RNAV / RNP / ADS-B / IRS / ground NAVAIDs / AIM |
| [GOOGLE-DEEPMIND.md](GOOGLE-DEEPMIND.md) | Gemini/Gemma/WeatherNext/… catalog + API key howto |
| [WEATHER-EXTERNAL.md](WEATHER-EXTERNAL.md) | WeatherNext and external forecast APIs (platform plane only) |
| [WEATHER-OPEN-STACK.md](WEATHER-OPEN-STACK.md) | Open multi-model WN2 substitute (AIFS+Atlas+FCN3) |
| [AIRSPACE.md](AIRSPACE.md) | ARTCC / oceanic centers, ZJX corridor notes, air-to-air SOPs |
| [DISPATCH-OPS.md](DISPATCH-OPS.md) | Part 91/135/121 ops gaps, booking→release pipeline, market gaps |
| [assets/](assets/) | ZJX maps, solution stack SVG, market-gaps PDF, whitepaper PDF |

**Trust rule:** simulation and assurance stay deterministic and evidence-bound.
External weather models, LLM drafts, and dispatch AI candidates live on the
platform plane until schema-validated and human-signed. See
[PLATFORM-EXTERNAL.md](../PLATFORM-EXTERNAL.md).

Primary locators are registered in `sources/primary-sources.json` (AIM, GNSS/PBN
notes, WeatherNext, dispatch market gaps). Large FAA PDFs are cited by URL;
digests cover bibliographic extractions and local asset bytes only.
