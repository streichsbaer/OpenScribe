# Popover Contract

## Scope

- Popover tab behavior for Live, History, and Stats.
- Sizing policy and parity guarantees.
- Smoke verification requirements.

## Tab switch path

All tab changes route through one state entry point.

- Segmented control clicks.
- Global hotkeys.
- Programmatic transitions.

## Sizing policy

Requested sizes are deterministic by tab or state.
Final height is capped by active display visible frame.

## Verification

Smoke runs validate click and hotkey parity with specific screenshot artifacts.

## Deep details

- Repository spec: [`docs/popover-spec.md`](https://github.com/streichsbaer/openscribe/blob/main/docs/popover-spec.md)
