# Devenv Removal Plan

## Overview

Remove devenv as a runtime dependency. Stackpanel's native modules (`languages/`, `modules/`, `services/`) now cover everything devenv provided. The `languages.*` modules added in this session replace devenv's `languages.go`, `languages.javascript`, and `languages.typescript`.

## What devenv currently provides (that we use)

| Feature | Devenv source | Stackpanel replacement |
|---|---|---|
| Go toolchain (GOPATH, GOROOT, packages) | `languages.go` via `.stackpanel/devenv.nix` | `stackpanel.languages.go` (new) |
| JS/Bun toolchain (node, bun, bun install) | `languages.javascript` via `.stackpanel/devenv.nix` | `stackpanel.languages.javascript` (new) |
| TypeScript compiler | `languages.typescript` via `.stackpanel/devenv.nix` | `stackpanel.languages.typescript` (new) |
| Git hooks (nixfmt, gofmt) | `git-hooks.hooks` via `.stackpanel/devenv.nix` | `stackpanel.git-hooks` + `inputs.git-hooks` (existing) |
| Packages (jq, git, nixd, etc.) | `packages` in `.stackpanel/devenv.nix` | `stackpanel.packages` in `config.nix` |
| Env vars (EDITOR, STEP_CA_*) | `env` in `.stackpanel/devenv.nix` | Already in `config.nix` or stackpanel modules |
| devenv-tasks-fast-build binary | `stackpanelInputs.devenv.packages` | Not needed (stackpanel has own task system) |

## Phase 1: Core Runtime (do now)

### 1.1 Flake adapter (`nix/flake/default.nix`)

Remove all devenv extraction logic. The adapter currently:
- Imports `devenv.flakeModule` (line 53)
- Reads `devenvEval = config.devenv.shells.default` (line 210)
- Extracts packages, env, processes from devenv eval (lines 213-220)
- Merges devenv packages/env into the shell (lines 257-272)
- Includes devenv-tasks-fast-build (lines 225-228)
- Configures `devenv.shells.default` with imports (lines 461-502)
- Sets `DEVENV_*` env vars in hook (lines 281-295, 387-389)

After removal: stackpanelEval provides everything via `devshellOutputs`. No devenv eval needed.

### 1.2 Flake inputs (`flake.nix`)

- Remove `devenv` input (line 31-32)
- Remove devenv cachix substituter + key (lines 9, 14)

### 1.3 Migrate `.stackpanel/devenv.nix` into `config.nix`

- Packages: `bun`, `nodejs_22`, `go`, `air`, `jq`, `git`, `nixd`, `nixfmt` -> `stackpanel.packages`
- Languages: already migrated to `stackpanel.languages.*`
- Git hooks: already handled by `stackpanel.git-hooks` module
- Env vars: `STACKPANEL_SHELL_ID`, `EDITOR`, `STEP_CA_*` -> `stackpanel.devshell.env` or existing modules

### 1.4 Remove `DEVENV_*` env vars from shell hook

These are set by the flake adapter but nothing in the native stackpanel flow needs them:
- `DEVENV_DOTFILE`
- `DEVENV_ROOT`
- `DEVENV_STATE`
- `DEVENV_RUNTIME`
- `DEVENV_PROFILE`
- `DEVENV_FLAKE_SHELL`
- `DEVENV_TASKS`
- `DEVENV_TASK_FILE`

## Phase 2: Adapter Files (can delete)

| File | Lines | Action |
|---|---|---|
| `nix/flake/modules/devenv.nix` | 120 | Delete |
| `nix/flake/devenv.nix` | 120 | Delete |
| `nix/lib/wrap-devenv.nix` | 217 | Delete |
| `nix/stackpanel/modules/devenv-services.nix` | 115 | Delete (if exists) |
| `nix/stackpanel/modules/devenv-languages.nix` | 114 | Delete (if exists) |
| `nix/stackpanel/modules/devenv-pre-commit.nix` | 129 | Delete (if exists) |
| `.stackpanel/devenv.nix` | 72 | Delete (after migrating config) |

## Phase 3: Internal Devenv Modules (migrate or delete)

| File | Purpose | Action |
|---|---|---|
| `nix/internal/devenv/devenv.nix` | Root aggregator | Delete |
| `nix/internal/devenv/docs/devenv.nix` | Docs process | Migrate to process-compose |
| `nix/internal/devenv/web/devenv.nix` | Web process | Migrate to process-compose |
| `nix/internal/devenv/tools/devenv.nix` | Mailpit service | Migrate to stackpanel services |

## Phase 4: Exports + Templates

| File | Action |
|---|---|
| `nix/flake/exports.nix` | Remove `devenvModules`, `wrapDevenv`, `devenv` template alias, devenv flakeModule alias |
| `nix/flake/templates/devenv/` | Delete entire directory |
| `nix/flake/templates/default/nix/devenv.nix` | Delete |
| `nix/flake/templates/default/flake.nix` | Remove devenv input |
| `nix/flake/templates/minimal/` | Remove devenv references |

## Phase 5: IDE + Shell Scripts

| File | Lines | Reference | Action |
|---|---|---|---|
| `nix/stackpanel/ide/lib/reference.json` | 6,8-9,13-14,66,68-70,77,79 | `.devenv/profile/*` paths | Replace with nix store / stackpanel paths |
| `nix/stackpanel/ide/devshell.sh` | 29,40,56,62,64,72,73 | `devenv.yaml`, `devenv enterShell` | Remove devenv mode, keep nix develop mode |
| `nix/stackpanel/lib/ide.nix` | 257,261 | `DEVENV_VSCODE_SHELL` | Rename to `STACKPANEL_VSCODE_SHELL` |
| `.envrc` | 66 | `watch_file devenv.nix` | Remove |
| `packages/scripts/lib/devshell.sh` | 26-28 | `DEVENV_ROOT` check | Remove, use `STACKPANEL_ROOT` |
| `.stackpanel/gen/ide/vscode/devshell-loader.sh` | 76-77 | Hash includes devenv files | Remove (regenerated) |
| `.stackpanel/gen/zed/devshell-loader.sh` | 76-77 | Hash includes devenv files | Remove (regenerated) |

## Phase 6: Nix Module Cleanup

| File | Lines | Reference | Action |
|---|---|---|---|
| `nix/stackpanel/tui/theme.nix` | 64-65 | `DEVENV_STATE` fallback | Remove fallback |
| `nix/stackpanel/modules/process-compose/module.nix` | 389-390 | `DEVENV_ROOT` check | Use `STACKPANEL_ROOT` |
| `nix/stackpanel/core/lib/envvars.nix` | 417-451 | `DEVENV_ROOT/STATE/DOTFILE/PROFILE/VSCODE_SHELL` defs | Remove |
| `nix/stackpanel/core/options/core.nix` | 167-177 | Deprecated `useDevenv` option | Remove |
| `.stackpanel/modules/generate-docs.nix` | 26 | `DEVENV_ROOT` fallback | Use `STACKPANEL_ROOT` |
| `nix/internal/devenv/docs/generate.nix` | 92 | `DEVENV_ROOT` fallback | Use `STACKPANEL_ROOT` |

## Phase 7: Go Code

| File | Lines | Reference | Action |
|---|---|---|---|
| `pkg/envvars/envvars.go` | 23,38,526-556 | `SourceDevenv`, `CategoryDevenv`, 4 env var defs | Remove |
| `pkg/exec/exec.go` | 84-86 | `DEVENV_ROOT` devshell detection | Use `STACKPANEL_ROOT` |
| `internal/tui/motd_data.go` | 693-694 | `devenv.nix`, `devenv.yaml` in hash | Remove |
| `internal/docgen/options.go` | 13-14,56 | devenv regex, icon mapping | Remove |
| `cmd/cli/env.go` | 81,98,109,263-264,278 | "devenv" source/category in CLI | Remove |
| `internal/agent/server/nixpkgs_search.go` | 134,443 | Comments + error message | Update text |

## Phase 8: CI + Docs (cosmetic)

| File | Action |
|---|---|
| `.github/workflows/devenv-cache.yml` | Remove devenv cachix entries |
| `.github/workflows/test-fixtures.yml` | Remove devenv cachix entries |
| `.github/workflows/ci.yml` | Remove devenv cachix entries |
| `AGENTS.md`, `CLAUDE.md`, etc. | Update architecture descriptions |
| `apps/docs/content/docs/` | Update user-facing docs |
| `.gitignore` | Keep `.devenv` entries for user compat (harmless) |
| `oxlint.json` | Keep `.devenv` ignore (harmless) |
| `tests/smoke-test.sh` | Remove devenv test mode |

## Risk Assessment

- **Low risk**: Phases 2-8 are deletions/renames -- they can't break runtime
- **Medium risk**: Phase 1 changes the shell construction -- needs testing
- **Key invariant**: After Phase 1, `nix develop --impure` must produce a shell with all packages, env vars, hooks, and starship working
- **Backwards compat**: External users importing `flakeModules.default` will lose devenv integration. They'll need to either add `stackpanel.languages.*` config or keep their own devenv setup separate.
