#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$ROOT_DIR/artifacts/live-provider-smoke/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT_DIR"

SETTINGS_FILE="$HOME/Library/Application Support/OpenScribe/Config/settings.json"
TEXT="${LIVE_SMOKE_TTS_TEXT:-Open Scribe live provider smoke test. Please transcribe this sentence and keep punctuation tidy.}"
VOICE="${LIVE_SMOKE_TTS_VOICE:-Samantha}"
RATE="${LIVE_SMOKE_TTS_RATE:-175}"
LANGUAGE="${LIVE_SMOKE_LANGUAGE:-auto}"
PLAY_AUDIO="${LIVE_SMOKE_PLAY_AUDIO:-0}"

TMP_AIFF="$OUT_DIR/live-smoke.aiff"
WAV_PATH="$OUT_DIR/live-smoke.wav"

say -v "$VOICE" -r "$RATE" -o "$TMP_AIFF" "$TEXT"
afconvert -f WAVE -d LEI16@16000 "$TMP_AIFF" "$WAV_PATH" >/dev/null 2>&1
rm -f "$TMP_AIFF"

echo "[live-provider-smoke] audio fixture: $WAV_PATH"
echo "[live-provider-smoke] text: $TEXT"

if [[ "$PLAY_AUDIO" == "1" ]]; then
  echo "[live-provider-smoke] playing generated audio"
  afplay "$WAV_PATH"
fi

settings_value() {
  local key="$1"
  if [[ -f "$SETTINGS_FILE" ]]; then
    plutil -extract "$key" raw -o - "$SETTINGS_FILE" 2>/dev/null || true
  fi
}

run_case() {
  local label="$1"
  local stt_provider="$2"
  local stt_model="$3"
  local polish_provider="$4"
  local polish_model="$5"
  local log_file="$OUT_DIR/${label}.log"

  echo "[live-provider-smoke] case=$label stt=$stt_provider/$stt_model polish=$polish_provider/$polish_model"
  RUN_LIVE_PROVIDER_SMOKE=1 \
  LIVE_SMOKE_AUDIO_PATH="$WAV_PATH" \
  LIVE_SMOKE_LANGUAGE="$LANGUAGE" \
  LIVE_SMOKE_STT_PROVIDER="$stt_provider" \
  LIVE_SMOKE_STT_MODEL="$stt_model" \
  LIVE_SMOKE_POLISH_PROVIDER="$polish_provider" \
  LIVE_SMOKE_POLISH_MODEL="$polish_model" \
  swift test --filter LiveProviderSmokeTests >"$log_file" 2>&1
  echo "[live-provider-smoke] passed: $label"
}

selected_stt_provider="$(settings_value transcriptionProviderID)"
selected_stt_model="$(settings_value transcriptionModel)"
selected_polish_provider="$(settings_value polishProviderID)"
selected_polish_model="$(settings_value polishModel)"

if [[ -n "${selected_stt_provider:-}" && -n "${selected_stt_model:-}" && -n "${selected_polish_provider:-}" && -n "${selected_polish_model:-}" ]]; then
  run_case "selected" "$selected_stt_provider" "$selected_stt_model" "$selected_polish_provider" "$selected_polish_model"
else
  echo "[live-provider-smoke] skipped selected case: settings file missing or incomplete"
fi

if [[ -n "${SCRIBE_OPENROUTER_API_KEY:-}" || -n "${OPENROUTER_API_KEY:-}" ]]; then
  run_case "openrouter" "openrouter_transcribe" "google/gemini-2.5-flash" "openrouter_polish" "openai/gpt-5-mini"
else
  echo "[live-provider-smoke] skipped openrouter case: missing SCRIBE_OPENROUTER_API_KEY or OPENROUTER_API_KEY"
fi

if [[ -n "${GEMINI_API_KEY:-}" ]]; then
  run_case "gemini" "gemini_transcribe" "gemini-3-flash-preview" "gemini_polish" "gemini-2.5-flash"
else
  echo "[live-provider-smoke] skipped gemini case: missing GEMINI_API_KEY"
fi

echo "[live-provider-smoke] complete"
echo "[live-provider-smoke] artifacts: $OUT_DIR"
