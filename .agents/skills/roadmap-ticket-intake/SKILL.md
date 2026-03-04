---
name: roadmap-ticket-intake
description: Triage and create OpenScribe roadmap issues by checking code coverage and duplicates, drafting clear acceptance criteria, collecting Stefan approval, creating issues, and verifying creation.
metadata:
  short-description: Triage and create roadmap issues
---

# Skill: roadmap-ticket-intake

## Purpose

Create high quality roadmap tickets with a repeatable intake flow.

## When to use

Use this skill when Stefan asks to create or refine GitHub Issues for roadmap items.

## Required inputs

- Candidate roadmap items in plain language.
- Repository slug, default: `streichsbaer/OpenScribe`.

## Workflow

1. Load guardrails and roadmap context.
- Read `SOUL.md`.
- Read `site-docs/ops/issue-tracking.md`.
- Read `site-docs/ops/label-conventions.md`.
- Read `site-docs/product/roadmap.md` when roadmap intent is relevant.

2. Normalize the request into focused issue slices.
- Keep one behavior change per ticket.
- Split mixed requests into separate issues.

3. Build an issue corpus with dedicated GitHub commands.
- Run issue collection script first for each slice:
- In normal workflow runs, do not execute script `--help` commands.

```bash
zsh .agents/skills/roadmap-ticket-intake/scripts/collect_issue_candidates.sh \
  --repo streichsbaer/OpenScribe \
  --title "<candidate title>" \
  --issue-query "<gh issue search query>" \
  --out "artifacts/roadmap-ticket-intake/<slug>-issues.json"
```

- This script uses dedicated issue commands (`gh issue list`) for:
  - Open issues.
  - Open `type/feature` issues.
  - Open `status/planned` and `status/in-progress` issues.
  - Query-seeded and title-seeded searches.

4. Run explorer semantic duplicate review from the issue corpus.
- Spawn `explorer` sub-agent with:
  - Candidate request text.
  - Path to `<slug>-issues.json`.
- Explorer must return:
  - `issue_match_count` integer.
  - `matched_issue_numbers` list.
  - `classification`: `duplicate` or `needs-code-check`.
  - One short `issue_evidence` line that includes the matched issue URL.
  - Recommended format: `Issue #<n> <url> - <concise reason>`.

5. Run strict issue gate using explorer issue evidence.

```bash
zsh .agents/skills/roadmap-ticket-intake/scripts/preflight_check.sh \
  --repo streichsbaer/OpenScribe \
  --title "<candidate title>" \
  --skip-issue-search \
  --issue-match-count "<explorer issue match count>" \
  --issue-evidence "<explorer issue evidence>" \
  --issues-only \
  --strict-no-create
```

- If result is `classification: duplicate`, stop immediately and ask for override.
- If result is `classification: needs-code-check`, continue to code gate.

6. Run code gate only for non-duplicates.
- Search codebase with `explorer` sub-agents first. Run explorers in parallel for multiple slices.
- Do not re-search files already covered by explorers.
- Each explorer must return:
  - `code_match_count` as an integer.
  - File path evidence for implemented behavior or explicit `no implementation found`.
- Then run final decisioning with script using both issue and code explorer evidence:

```bash
zsh .agents/skills/roadmap-ticket-intake/scripts/preflight_check.sh \
  --repo streichsbaer/OpenScribe \
  --title "<candidate title>" \
  --skip-issue-search \
  --issue-match-count 0 \
  --issue-evidence "<explorer issue evidence: no duplicate found>" \
  --skip-code-search \
  --code-match-count "<explorer code match count>" \
  --code-evidence "<explorer short evidence>" \
  --strict-no-create
```

- Fallback when explorer is unavailable for issue matching or code matching:

```bash
zsh .agents/skills/roadmap-ticket-intake/scripts/preflight_check.sh \
  --repo streichsbaer/OpenScribe \
  --title "<candidate title>" \
  --code-query "<rg query>" \
  --issue-query "<gh issue search query>" \
  --strict-no-create
```

7. Classify each slice.
- Script decision values:
  - `classification: duplicate` with `decision: DO_NOT_CREATE`
  - `classification: already-implemented` with `decision: DO_NOT_CREATE`
  - `classification: needs-code-check` with `decision: REQUIRES_CODE_CHECK`
  - `classification: new` with `decision: CAN_CREATE`
- Manual override:
  - `addition` is allowed only when Stefan explicitly asks to track extra scope despite related existing work.

8. Duplicate and implementation gate.
- If decision is `DO_NOT_CREATE`, stop before draft creation.
- Do not run `gh issue view` automatically after `DO_NOT_CREATE`.
- Use the existing evidence line and ask a binary override question:
  - `Existing issue coverage found. Create a new ticket anyway? (yes/no)`
- Do not create issues until Stefan answers.

9. Draft issue preview.
- Include title, labels, problem statement, proposed outcome, and acceptance criteria.
- Labels must include one `type/*`, one `status/*`, and one `area/*`.

10. Approval gate.
- Get explicit approval from Stefan before creating issues.
- If approval is already present in the active conversation, cite that message.

11. Create issue after approval.

```bash
gh issue create --repo streichsbaer/OpenScribe \
  --title "[Work]: <title>" \
  --label "type/feature" --label "status/planned" --label "area/ui" \
  --body "<markdown body>"
```

12. Verify creation.

```bash
zsh .agents/skills/roadmap-ticket-intake/scripts/verify_issue.sh \
  --repo streichsbaer/OpenScribe \
  --issue <number>
```

## Output contract

For each requested item, report:
- Classification: duplicate, addition, or new.
- Evidence summary from issue explorer review and code explorer review.
- Decision code: `CAN_CREATE` or `DO_NOT_CREATE`.
- Report whether issue gate stopped the flow early.
- Include the issue corpus artifact path used for duplicate review.
- Include issue URL in duplicate evidence output.
- Draft issue content and final labels.
- Created issue URL once verified.

## Constraints

- Follow `site-docs/ops/label-conventions.md` exactly.
- Use dedicated `gh issue list` collection before semantic duplicate review.
- Use explorer sub-agents for issue duplicate review and code coverage review.
- Prefer explorer sub-agents for codebase checks and run them in parallel when useful.
- Run issue gate first to allow early stop on duplicates.
- Keep issue text concrete and testable.
- Do not create issues when decision is `DO_NOT_CREATE` unless Stefan gives explicit override.
- Do not create issues before approval.
