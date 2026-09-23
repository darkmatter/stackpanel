# 0006 — `.stack/` is the single stackpanel directory, with one config file and JSON machine data

- **Status**: Accepted
- **Date**: 2026-09-23
- **Related**: [ADR 0004](./0004-agent-api-on-connect.md)

## Context

Stackpanel is aimed at developers who are not Nix natives. For them the
most important property of the project directory is that every setting has
one obvious home, and that the file the Studio edits is the file Nix reads.

The September 2026 review found about ten places a config value can live,
added one after another without the previous one being removed:

| Location | State |
| --- | --- |
| `.stack/config.nix` | Canonical; edited by humans and by the Studio (syntax-tree patching) |
| Split imports (`import ./config.apps.nix`) | Supported; one agent write path inlines them back |
| `.stack/config/` (haumea tree) | Optional; shallow-overrides `config.nix`; needs haumea in the user's flake; its map-entity list is hand-synced with Go and has drifted |
| `.stack/data/<entity>.nix` | Go reads and writes it when present; Nix reads only `data/packages.nix`, so Studio edits can land in files Nix never reads |
| `.stack/data.nix` | Scaffolded by the `default`, `minimal`, and `haumea` templates, documented as "merged with config.nix"; nothing reads it |
| `.stack/_internal.nix` | The loader's first choice; nothing writes it |
| `.stack/config.local.nix` | Personal overrides (gitignored) |
| `.stack/modules/` | Full NixOS-module escape hatch |
| `.stackpanel/{config.nix,_internal.nix,config/}` | Legacy directory name, still probed (~100 references across Go, Nix, and TypeScript) |

Runtime files were split between `state/` and `profile/` (plus `keys/`,
`gen/`, `bin/`, `.token`, `secrets/state/`, `secrets/bin/`), taking 14
`.gitignore` lines; the `state/`/`profile/` split already broke the TUI
certificate check. Machine-synced data (GitHub collaborators, the SSH-age
cache) was written as Nix source by Go, which is where several quoting and
formatting bugs lived, and one writer and its readers disagreed about the
directory.

## Decision

`.stack/` holds every stackpanel source of truth and all stackpanel state,
in one layout:

```
.stack/
  config.nix        the one config file: plain data, edited by humans and the Studio
  config.local.nix  personal overrides (gitignored)
  modules/          Nix escape hatch; the agent never writes here
  data/             machine-synced, committed, never hand-edited (JSON)
  secrets/          SOPS-encrypted values and recipients
  machines/         deploy targets
  gen/              generated files (gitignored)
  state/            everything machine-local (gitignored): keys, profile, binaries, tokens, caches
```

1. **`config.nix` is Nix, but plain data.** No `let` blocks or logic; logic
   moves to `modules/`. It reads like JSON with `=` and `;`, and the
   Studio's syntax-tree edits stay safe. Splitting it with plain
   `import ./<file>.nix` is allowed and understood by the patcher.
2. **Machine data is JSON under `data/`.** It is lockfile-like: synced from
   outside and committed so Nix evaluation stays pure. Go writes JSON; Nix
   reads it with `builtins.fromJSON`. Go no longer emits Nix source for
   data. Studio-installed packages become an entry in `config.nix`.
3. **Two ignored directories:** `gen/` for anything regenerable, `state/`
   for anything machine-local. What is safe to delete is obvious.
4. **The project root is the nearest directory containing
   `.stack/config.nix`.** The `.stackpanel-root` marker goes away, and the
   four root-finding implementations become one rule.
5. **Removed:** the `.stackpanel/` fallbacks, `_internal.nix`, `data.nix`
   (from templates and the proto-nix schema options), Go's
   `data/<entity>.nix` fallback, and the haumea tree layout.
6. **Files outside `.stack/` are generated projections.** Some files must
   live where their tool looks: `.envrc`, `turbo.json`, the workspace
   packages under `packages/gen/`, per-app integration outputs such as
   `apps/api/fly.toml`. Each is fully regenerated, carries a header
   pointing back to its `.stack/` source, and is recorded in the CLI's file
   ledger so `stack doctor` can list and clean them.
7. **One cutover, no compatibility window.** Go, Nix, TypeScript,
   templates, and docs change together. `stack doctor` fails with exact
   move instructions if it finds a legacy path, instead of silently
   supporting it.

## Consequences

**Pros**

- One home per value; the Studio writes exactly what Nix reads.
- Removes a class of bugs: Nix source emitted by Go for data, a key encoding
  shared by hand between Go and Nix, and writers and readers using different
  directories.
- Smaller loader and writer in both Go and Nix; no extra flake input for
  users.

**Cons and risks**

- Projects using the haumea tree or the legacy directory must migrate; the
  doctor check makes that explicit.
- Dropping the tree layout gives up per-entry files. If merge conflicts in
  `config.nix` become a problem, split it with imports rather than bringing
  back a second layout.

**Follow-ups** (tracked under stackpanel-thq.9)

- Decide whether `.stack/gen/` is committed (AGENTS.md says yes,
  `.gitignore` says no) and make the docs match.

## Alternatives considered

- **Keep the haumea tree as an option.** Solves per-entry diffs and merge
  conflicts, but it is a second layout both Go and Nix must support, adds a
  flake input, has surprising precedence (tree wins, shallowly), and its
  hand-synced key encoding had already drifted.
- **A separate agent-written overlay (`data.nix`).** Tried already: two
  files per setting with precedence rules, and it fell out of use without
  being removed.
- **Keep machine data as Nix files.** Requires Go to emit Nix source safely,
  which is where the quoting and formatter bugs came from.
- **Keep a compatibility window for `.stackpanel/`.** Rejected: silent
  fallbacks are how the current ten locations accumulated.

## References

- stackpanel-thq.9 (consolidation), stackpanel-thq.7 (writer/reader
  directory mismatch)
- `nix/flake/load-config.nix`, `apps/stackpanel-go/pkg/nixdata/{paths.go,entities.go,store.go}`,
  `nix/stackpanel/db/lib/proto.nix`, `nix/flake/templates/`
