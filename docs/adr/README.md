# Architecture Decision Records

This directory contains Architecture Decision Records (ADRs) for the
stackpanel monorepo. Each ADR captures a significant decision — its
context, the choice made, the consequences, and the alternatives
considered — at the moment we made it. ADRs are immutable: when we
revisit a decision we add a new ADR that supersedes the previous one
rather than editing history.

## Convention

- Filenames follow `NNNN-kebab-case-title.md`, where `NNNN` is a
  zero-padded sequential 4-digit number. The next ADR is whichever
  number is one higher than the highest existing file.
- The first H1 inside the file is the title (matches the filename).
- Each ADR has the following sections, in order:
  - **Status** — Proposed | Accepted | Superseded by NNNN | Deprecated.
  - **Date** — `YYYY-MM-DD`.
  - **Context** — what's the problem, why now.
  - **Decision** — the actual choice, in present tense.
  - **Consequences** — pros, cons, risks, follow-ups.
  - **Alternatives considered** — every realistic option we rejected and
    why.
  - **References** — links to related code, commits, PRs, issues.

## Index

- [0001 — Runtime secrets are decrypted via `@gen/env`, not forwarded as Worker env vars](./0001-runtime-secrets-via-gen-env-loader.md) — *Superseded by 0003*
- [0002 — Database migrations are applied programmatically at app startup, not via `drizzle-kit push`](./0002-runtime-startup-migrations.md)
- [0003 — Build-time env injection with `effect/Config` for typed redacted access](./0003-build-time-env-injection-with-effect-config.md)
