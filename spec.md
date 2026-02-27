# SmartTranscript V1 Spec

## Target
- Native Apple Silicon macOS app (tested target: macOS 26, min package platform currently set to macOS 15 for tool compatibility).
- Menubar-only utility app.

## Core Flow
1. Global hotkey toggles recording.
2. Audio is captured to `audio.wav.part`.
3. On stop, audio is finalized atomically to `audio.wav`.
4. STT runs via selected provider.
5. Polish runs via selected LLM provider with `Rules/rules.md`.
6. Session artifacts are written: `audio.wav`, `session.json`, `raw.txt`, `polished.md`, `feedback.log.jsonl`.
7. Feedback proposes unified diff for rules; user approves/rejects; approve triggers auto re-polish.

## Defaults
- Start/stop hotkey default: `Fn + Space` (configurable).
- Copy hotkey default: `Ctrl + Option + V` (configurable).
- If hotkey registration fails, app shows blocking warning and requires manual change.
- Default STT provider: local `whisper.cpp`.
- Default local model: `base`.
- Language: `auto`.
- Copy-on-complete: enabled.

## Storage Layout
Root: `~/Library/Application Support/SmartTranscript`

- `Recordings/YYYY-MM-DD/HHmmss-<uuid>/audio.wav`
- `Recordings/YYYY-MM-DD/HHmmss-<uuid>/session.json`
- `Recordings/YYYY-MM-DD/HHmmss-<uuid>/raw.txt`
- `Recordings/YYYY-MM-DD/HHmmss-<uuid>/polished.md`
- `Recordings/YYYY-MM-DD/HHmmss-<uuid>/feedback.log.jsonl`
- `Rules/rules.md`
- `Rules/rules.history.jsonl`
- `Models/whisper/ggml-<model>.bin`
- `Config/settings.json`

## Providers
- STT:
  - Local `whisper.cpp`
  - OpenAI Whisper API
  - Groq Whisper API
- Polish:
  - OpenAI chat API
  - Groq chat API

## Feedback Loop
- User enters feedback text.
- App asks selected polish provider to return unified diff for `Rules/rules.md`.
- App validates patch scope and context.
- UI displays diff for approval.
- On approval, rules are atomically updated, history log appended, and current session re-polishes.

## Out of Scope (V1)
- Streaming transcription.
- Accessibility typing injection.
- Sync/team dictionaries.
- Speaker diarization and timestamps.

## Build/Run
- `swift build`
- `swift run SmartTranscript`

For full app signing/notarization and polished packaging, use a follow-up release phase.
