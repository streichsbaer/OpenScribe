# Storage Contract

Root path:

`~/Library/Application Support/OpenScribe`

## Session artifacts

- `Recordings/YYYY-MM-DD/HHmmss-<uuid>/audio.m4a`
- `Recordings/YYYY-MM-DD/HHmmss-<uuid>/session.json`
- `Recordings/YYYY-MM-DD/HHmmss-<uuid>/raw.txt`
- `Recordings/YYYY-MM-DD/HHmmss-<uuid>/polished.md`

## Shared data

- `Rules/rules.md`
- `Rules/rules.history.jsonl`
- `Stats/usage.events.jsonl`
- `Models/whisper/ggml-<model>.bin`
- `Config/settings.json`

## Why this matters

This contract keeps each recording durable and inspectable.
