# Roadmap

_Last updated: March 6, 2026_

This is the canonical roadmap summary for OpenScribe.

Execution lives in GitHub Issues. Shipped behavior belongs in the product spec and feature docs. This page stays short and points to the current tracked work.

## Live tracker

Roadmap execution is tracked in GitHub Issues.

- [Open features](https://github.com/streichsbaer/openscribe/issues?q=is%3Aopen+label%3Atype%2Ffeature)
- [Planned](https://github.com/streichsbaer/openscribe/issues?q=is%3Aopen+label%3Astatus%2Fplanned)
- [In progress](https://github.com/streichsbaer/openscribe/issues?q=is%3Aopen+label%3Astatus%2Fin-progress)
- [Done](https://github.com/streichsbaer/openscribe/issues?q=is%3Aclosed+label%3Astatus%2Fdone)
- Tracking model details: [Issue Tracking](../ops/issue-tracking.md)

## Current roadmap themes

### R1. Session History Browser

- Status: In progress.
- Implemented baseline: browse, open, replay, re-run processing, load more, and bulk delete are live.
- Open ticket: [#12 Add History tab search and filtering](https://github.com/streichsbaer/openscribe/issues/12)

### R2. Processing Statistics and Cost Tracking

- Status: In progress.
- Implemented baseline: usage ledger, aggregate stats, latest run metrics, streaks, WPM, provider usage, and current-session stats are live.
- Open ticket: [#13 Add pricing catalog and cost tracking to Stats](https://github.com/streichsbaer/openscribe/issues/13)

### R3. Price Catalog and Savings View

- Status: Planned.
- Tracked in: [#13 Add pricing catalog and cost tracking to Stats](https://github.com/streichsbaer/openscribe/issues/13)

### R4. Retention Policy and Cleanup

- Status: Planned.
- Open ticket: [#14 Add retention policy and cleanup controls](https://github.com/streichsbaer/openscribe/issues/14)

### R5. Documentation Pyramid and Agent-Facing Docs Skill

- Status: In progress.
- Implemented baseline: docs landing, product section, guides, reference docs, and docs visual review automation are live.
- Open tickets:
  [#11 Capture matching light and dark docs screenshots](https://github.com/streichsbaer/openscribe/issues/11),
  [#15 Add agent-facing docs Q and A skill](https://github.com/streichsbaer/openscribe/issues/15)

### R6. Per-Recording Temporary Instructions

- Status: Planned.
- Open ticket: [#16 Add per-recording temporary instructions](https://github.com/streichsbaer/openscribe/issues/16)

### R7. Wake Phrase Research Track

- Status: Planned.
- Open ticket: [#17 Research wake phrase and voice command mode](https://github.com/streichsbaer/openscribe/issues/17)

### R8. Test Roadmap

- Status: In progress.
- Implemented baseline: deterministic UI smoke captures, click and hotkey parity checks, and menubar state capture are live.
- Open ticket: [#18 Add baseline image diffs and CI failure artifacts for UI smoke](https://github.com/streichsbaer/openscribe/issues/18)

## Additional planned slices

Other planned work lives in the issue tracker, including provider fallback, provider advanced parameters, polish presets, direct-submit keyboard handling, and reminder workflows.
