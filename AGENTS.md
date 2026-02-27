# SmartTranscript Agent Rules

## Build Policy

- Implement the current behavior directly.
- Do not add migration code, deprecation handling, compatibility shims, fallback paths, or legacy settings upgrades unless the user explicitly requests them.
- Prefer a single clear path that works now over backward-compatibility logic.

## Writing Style

- Do not use em dashes.
- Do not use contrastive negation phrasing such as "it is not X, it is Y."

## SOUL

- Load `SOUL.md` at the start of work.
- Always read `SOUL.md` before planning or editing code in each new session.
- Treat `SOUL.md` as the product and engineering voice for this repository.
- Use `SOUL.md` to guide priorities, privacy stance, and communication tone.

## Git Commit Policy

- Commit in small logical slices.
- Do not mix unrelated changes in one commit.
- Use subject format: `<type>: <imperative summary>`.
- Allowed commit types: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`.
- Keep subject line at 72 characters or fewer.
- Use concise, factual tone in commit messages.
- Add a commit body only when context is needed, with `Why` and `What`.
- Do not amend or rewrite prior commits unless explicitly requested.
- If unrelated files are already staged, commit only intended paths.
