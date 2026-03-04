# Contributing to OpenScribe

OpenScribe uses an issue-first contribution model.

## Contribution model

- Open an issue instead of opening an unsolicited pull request.
- Write the issue as a concrete prompt with clear acceptance criteria.
- Maintainer and Scribe implement accepted work and open the PR from this repository.

If you already have code or an agent-generated draft, open an issue and include links to:

- A fork branch with the code, or
- A coding-agent session with implementation details.

The maintainer can port the changes directly or adapt them.

## Issue quality bar

Every issue should include:

1. Problem statement.
2. Proposed outcome.
3. Acceptance criteria that can be verified.
4. Optional constraints and non-goals.
5. Optional implementation notes or references.

## Labels

Use the label taxonomy from `site-docs/ops/label-conventions.md`:

- one `type/*`
- one `status/*`
- one `area/*`

## Pull requests

Maintainer and Scribe authored pull requests are the default merge path.
External pull requests may be closed and redirected to an issue.

## Security notes

- CI workflows follow least-privilege and supply-chain hardening rules from `AGENTS.md`.
- External review findings are triaged before merge.
