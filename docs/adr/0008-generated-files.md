# 0008 — Conventions when generating files

- **Status**: Accepted
- **Date**: 2026-11-07
- **Related**: [ADR 0006](./0006-single-stack-directory.md)

## Context

Stackpanel's core value is around file generation. It frees you from constraints put on
you by all the tools you need to build your app. This is true of many Nix-based tools, not just Stackpanel. Typically they provide a wrapped package that "injects"
configuration, but in a development environment, that would mean the integration with
your IDE would stop working, among other issues.

Therefore it is common to generate the file into the repo itself and gitignore it. This works for purely local/runtime configs, but if that file is required for your app to build, gitignoring it causes an issue. Not only would CI fail when building outside the devshell, but Nix flakes cannot see untracked files that aren't checked into git—making them invisible to pure Nix evaluation. That means some generated files must be checked in, while others (such as Nix store symlinks or machine-specific IDE terminal paths) must be gitignored.

At the same time, we cannot force all checked-in or all ignored files into a single directory or filename suffix: tools require exact filenames and locations (e.g. `.zed/settings.json`, `.oxlintrc.json`, `.sops.yaml`, `process-compose.yaml`), and generated workspace packages (e.g. `packages/gen/env/`) must live under `packages/` to respect Turborepo workspace boundaries.

This ADR defines the convention and patterns that all modules use so Stackpanel works seamlessly across all of these scenarios.

## Decision

- **There is no constraint on what a file can be named.** Tools rely on exact filenames, and Stackpanel must never impose naming constraints when its goal is to remove tool friction.
- **There is no constraint on _where_ a file can be generated.** Just as filenames are dictated by external tools and monorepo boundaries, file locations are too.
- **A declarative manifest (`stackpanel.files.entries`) tracks every generated file across four orthogonal axes:**
  1. `format` (`"text"` | `"json"` | `"yaml"` | `"toml"` | `"lines"` | `"derivation"` | `"symlink"`) — how the content is produced.
  2. `writer` (`"full"` | `"block"` | `"paths"`) — how much of the on-disk file Stackpanel owns (the entire file, a marker-delimited `# ── BEGIN stackpanel ──` block, or specific JSON/YAML/TOML key paths).
  3. `adopt` (`"none"` | `"backup"` | `"refuse"`) — how Stackpanel handles first contact with a pre-existing user file.
  4. `gitignore` (`true` | `false`) — whether the file is ephemeral/machine-local (ignored) or part of the repository's buildable source tree (committed).
- **Smart defaults on the `gitignore` axis:**
  - `gitignore` defaults to `true` for `format = "symlink"` (which typically points into `/nix/store/` or `.stack/gen/`) and for any path under `<home>/{gen,profile,state,keys,bin}/` or `.tasks/` (`*/.tasks/`).
  - `gitignore` defaults to `false` (committed) for all other generated files (such as `packages/gen/**`, `.sops.yaml`, `turbo.json`, and patched `package.json` manifests).
  - Modules can explicitly set `gitignore = true` on any ephemeral file generated outside `.stack/` (e.g. `/devshell`, `.envrc.local`, `.vscode/settings.json`, `.zed/settings.json`).
- **The manifest is the single source of truth for `.gitignore`, `stack doctor`, and the Studio UI:**
  - `nix/stackpanel/core/default.nix` automatically collects all enabled `stackpanel.files.entries` with `gitignore = true` and emits them into the managed `# ── BEGIN stackpanel ──` block in `.gitignore` (skipping entries already covered by directory-level rules like `.stack/gen/` or `.tasks/`).
  - The pure and preflight file manifests (`STACKPANEL_FILES_MANIFEST`, `STACKPANEL_FILES_PREFLIGHT_MANIFEST`, and `stackpanel.files._plan`) include `gitignore` on every entry.
  - `stack doctor` (`FilesReconciler` and `FileopsReconciler`) checks whether any `gitignore = true` entry is tracked in the git index (`git ls-files`) and emits a warning with `fix: git rm --cached <path>`.
  - The Agent (`/api/nix/files`) and Studio UI (**Files** and **Inspector** panels) display a `Gitignored` vs `Committed` (or `Committed (block)` / `Committed (paths)`) badge on every generated file.

## Consequences

**Pros**

- **Zero drift between file declarations and `.gitignore`:** Modules declare `gitignore = true` (or `format = "symlink"`) directly on the `stackpanel.files.entries.<path>` definition instead of maintaining separate `stackpanel.gitignore.entries` lists.
- **No artificial path or naming restrictions:** Files can be placed wherever tools or Turborepo require (`.zed/settings.json`, `process-compose.yaml`, `packages/gen/env/**`) while still having explicit, inspectable git-tracking semantics.
- **Self-auditing repository state:** `stack doctor` catches ephemeral generated files that were accidentally `git add`-ed before `.gitignore` was applied, and provides the exact `git rm --cached` fix command.
- **Clear visibility for users:** Both `.gitignore` (managed block) and the Studio UI clearly distinguish ephemeral files from committed codegen and co-owned (`block` / `paths`) config files.

**Cons**

- Developers cannot rely purely on a filename suffix (like `*.gen.*`) to know if an arbitrary root dotfile is generated; they rely on the managed `.gitignore` block, `stack doctor`, or the Studio **Files** panel.
- Committed generated files (`gitignore = false`) must be kept up to date in git when their upstream Nix config or schemas change, enforced by `stack doctor --strict` in CI.

**Follow-ups**

- Optionally emit a managed `# ── BEGIN stackpanel ──` block in `.gitattributes` marking `gitignore = false` + `writer = "full"` entries as `linguist-generated=true` so GitHub PR diffs collapse them automatically.
- Resolve the `.stack/gen/` documentation discrepancy noted in [ADR 0006](./0006-single-stack-directory.md) (completed in `AGENTS.md`: `.stack/gen/` is gitignored; committed codegen lives in `packages/gen/` or repo-level `gitignore = false` entries).

## Alternatives considered

- **Force all ignored or committed generated files into a single directory (e.g. `.stack/gen/`):** Rejected because many tools require config files at fixed paths in the repo root or app directories (`.zed/settings.json`, `process-compose.yaml`, `.sops.yaml`), and Turborepo workspace packages (`packages/gen/env/`) must reside in `packages/` to respect workspace boundaries.
- **Require a `*.gen.<ext>` naming suffix on all generated files:** Rejected because external tools look for fixed filenames (`turbo.json`, `package.json`, `.oxlintrc.json`) that cannot be renamed.
- **Maintain `stackpanel.gitignore.entries` manually in each module:** Rejected because separate lists drift from `stackpanel.files.entries` (for example, `.envrc.local` was previously generated without a corresponding `.gitignore` entry) and leave the manifest unaware of whether a file is meant to be tracked or ignored.

## References

- `nix/stackpanel/files/default.nix` (`entryType.options.gitignore`, `manifestEntries`, `preflightManifestEntries`, `planEntries`)
- `nix/stackpanel/core/default.nix` (automatic `.gitignore` block population from `files.entries`)
- `apps/stackpanel-go/internal/reconcile/rc_files.go` & `rc_fileops.go` (`checkGitignoredNotTracked`)
- `apps/stackpanel-go/internal/agent/server/nix_files.go` (`/api/nix/files`)
- [ADR 0006 — `.stack/` is the single stackpanel directory](./0006-single-stack-directory.md)
