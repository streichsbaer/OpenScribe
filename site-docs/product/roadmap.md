# Roadmap

_Last updated: March 3, 2026_

This is the canonical roadmap summary for OpenScribe.

## Live tracker

Roadmap execution is tracked in GitHub Issues.

- [Open features](https://github.com/streichsbaer/openscribe/issues?q=is%3Aopen+label%3Atype%2Ffeature)
- [Planned](https://github.com/streichsbaer/openscribe/issues?q=is%3Aopen+label%3Astatus%2Fplanned)
- [In progress](https://github.com/streichsbaer/openscribe/issues?q=is%3Aopen+label%3Astatus%2Fin-progress)
- [Done](https://github.com/streichsbaer/openscribe/issues?q=is%3Aclosed+label%3Astatus%2Fdone)
- Tracking model details: [Issue Tracking](../ops/issue-tracking.md)

## Status snapshot

- R1. Session History Browser: In progress.
  - Completed: browse, open, replay audio, re-run processing, row actions, bulk delete.
  - Open: session search and filtering.
- R2. Processing Statistics and Cost Tracking: In progress.
  - Completed: usage ledger (`Stats/usage.events.jsonl`), aggregate stats, latest run metrics, streak and WPM cards, token capture when provided by provider APIs.
  - Open: cost calculator and configurable pricing table.
- R3. Price Catalog and Savings View: Planned.
- R4. Retention Policy and Cleanup: Planned.
- R5. Documentation Pyramid and Agent-Facing Docs Skill: Planned.
- R6. Per-Recording Temporary Instructions: Planned.
- R7. Wake Phrase Research Track: Planned.
- R8. Test Roadmap: In progress.
  - Completed: deterministic UI smoke captures and parity checks for click and hotkey paths.
  - Open: baseline image diff workflow and CI failure visualization.

## R1. Session History Browser

- Goal: let users browse, search, and reopen previous sessions.
- Scope:
  - List sessions from `Recordings/` sorted by time.
  - Show provider and model, duration, state, and short transcript preview.
  - Open one session to inspect raw and polished text and replay audio.
  - Re-run transcribe and polish from history view.
- Current behavior: show latest 10 entries first, then load more with `next 10`, `next 25`, `next 50`, or `whole`.
- Acceptance:
  - User can locate and open any historical session without Finder.
  - User can re-run processing from a selected history item.

## R2. Processing Statistics and Cost Tracking

- Goal: show per-session and aggregate pipeline metrics, including cost.
- Scope:
  - Track per-step latency (`recording`, `transcribing`, `polishing`).
  - Track provider and model usage per step.
  - Compute estimated cost by provider and model price table.
  - Show totals (today, 7 days, 30 days, all time).
- Data contract:
  - Immutable usage ledger file: `Stats/usage.events.jsonl`.
  - Write one ledger record per completed step with timestamp and session ID.
- Acceptance:
  - User can see session-level and aggregate time and cost numbers.
  - Cost view distinguishes free local runs from paid API runs.

## R3. Price Catalog and Savings View

- Goal: maintain transparent pricing assumptions and show practical savings.
- Scope:
  - Add local price catalog file, example: `Config/pricing.json`.
  - Version the catalog and show last-updated date in UI.
  - Add simple savings comparison view against user-entered subscription baseline.
- Default behavior:
  - Use maintained app pricing table.
  - User can override baseline subscription values for comparison.
- Acceptance:
  - UI shows both actual estimated spend and baseline comparison delta.

## R4. Retention Policy and Cleanup

- Goal: allow automatic cleanup without breaking analytics.
- Scope:
  - Retention modes: `Keep forever`, `Delete audio only after X days`, `Delete full sessions after X days`.
  - Scheduled cleanup at app launch and optional daily run.
  - Before deletion, preserve derived metrics in ledger.
- Proposed default: `Keep forever`.
- Acceptance:
  - Cleanup removes targeted files only.
  - Statistics remain consistent after cleanup.

## R5. Documentation Pyramid and Agent-Facing Docs Skill

- Goal: make docs easy to navigate for humans and agents.
- Scope:
  - Top-level overview page with clickable deep dives.
  - Feature pages for recording, providers, polish, history, stats, and release.
  - Add dedicated docs Q and A skill in `.agents/skills/docs/` that indexes and answers from repo docs.
- Acceptance:
  - New contributor can navigate from overview to implementation details quickly.
  - Agent can answer product and technical questions from local docs with source references.

## R6. Per-Recording Temporary Instructions

- Goal: support one-off dictation rules for a single recording.
- Scope:
  - Optional instruction preamble mode at recording start.
  - User speaks instructions, then marks start of content.
  - Pass parsed instructions into polish prompt context for this session only.
  - Setting toggle to enable or disable this mode.
- Acceptance:
  - Session can include temporary style rules without changing global `rules.md`.
  - Instructions are visible in session metadata for traceability.

## R7. Wake Phrase Research Track

- Goal: evaluate optional always-listening mode for hands-free start or stop.
- Scope:
  - Start transcript on action phrase.
  - Auto-stop after silence cooldown.
  - Voice commands: `pause recording`, `resume recording`, `stop recording`.
  - Define coexistence constraints with other macOS microphone users.
- Acceptance:
  - Clear feasibility decision with UX and technical constraints documented.

## R8. Test Roadmap

- Scope:
  - Add baseline comparison to existing menubar icon snapshots:
    - idle, recording-working, recording-paused, recording-no-audio, transcribing, polishing
    - system, light, dark appearance modes
  - Add thresholded image-diff reporting and CI-friendly failure output.

## Notes

- This page stays concise enough for navigation and reviews.
- GitHub issue filters provide the current execution view.
