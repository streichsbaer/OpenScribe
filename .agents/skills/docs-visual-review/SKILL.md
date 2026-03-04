---
name: docs-visual-review
description: Build OpenScribe and docs, serve docs with uv, run Playwright CLI screenshots across key pages, then shut down the local docs server cleanly.
metadata:
  short-description: Visual docs review with Playwright
---

# Skill: docs-visual-review

## Purpose

Run fast and repeatable visual QA for the docs site with local automation.

## Use this when

- You need to verify docs layout or styling changes.
- You want deterministic screenshots for review.
- You want one command that builds, serves, captures, and tears down.

## Invocation in agent sessions

- Invoke by skill name and optional params, for example: `$docs-visual-review --out artifacts/docs-visual/latest`.
- The agent runs and verifies the workflow steps.

## Run

From repo root:

```bash
zsh .agents/skills/docs-visual-review/scripts/run.sh
```

Include app build precheck:

```bash
zsh .agents/skills/docs-visual-review/scripts/run.sh --with-swift-build
```

Custom output path:

```bash
zsh .agents/skills/docs-visual-review/scripts/run.sh --out artifacts/docs-visual/latest
```

Keep server running after capture:

```bash
zsh .agents/skills/docs-visual-review/scripts/run.sh --keep-server
```

## Workflow

1. Verify required tools (`uv`, `playwright-cli`, `curl`, `swift`).
2. Use repo-local uv cache under `.build/uv-cache`.
3. Build docs (`uv run mkdocs build --strict`) unless skipped.
4. Start docs server (`uv run mkdocs serve`).
5. Open Playwright browser, navigate to key docs routes, and capture full-page screenshots.
6. Write logs and a short report.
7. Close Playwright and stop the docs server (unless `--keep-server` is set).
8. Optional precheck: run `swift build` only when `--with-swift-build` is set.

## Outputs

Default output directory:

- Relative to repo root: `artifacts/docs-visual/<timestamp>/`

Artifacts:

- `swift-build.log`
- `mkdocs-build.log`
- `mkdocs-serve.log`
- `playwright.log`
- `home.png`
- `menu-and-settings.png`
- `product-spec.png`
- `report.md`
