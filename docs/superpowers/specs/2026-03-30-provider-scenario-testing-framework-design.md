# Provider Scenario Testing Framework

> **Status:** Approved design — ready for implementation.
>
> **Related implementation plan:** `docs/superpowers/plans/2026-03-30-provider-scenario-testing-framework.md`
>
> **Source of truth for:** the approved framework architecture, component split, execution model, and guardrails for the `tests/lib/` + `tests/scenarios/` layout.

## Problem

Deployment and provisioning regression coverage is currently growing through one-off shell scripts.
The primary example is `tests/provision-hetzner-e2e.sh`, a 368-line shell script that embeds all of
the following directly:

- prerequisite checking (tool availability, SOPS access, token validation)
- ephemeral cloud resource lifecycle (server creation, SSH key registration, IP resolution)
- config override injection and backup/restore (`.stack/config.local.nix` mutation)
- SSH availability polling and authentication verification
- CLI invocation (mode-conditional `stackpanel provision` flags)
- cleanup (server deletion, SSH key deletion, config restore) in a trap

When the next developer needs a similar test for a different provider or deployment backend, the
natural path is to copy this script and modify it.  Each copy re-implements the same concerns
independently, drifting over time and making the whole test surface harder to maintain.

Concretely:

- cleanup logic is the most failure-prone part of cloud tests, yet it is duplicated per-script
- config override and restore is a subtle shared concern that every Hetzner-adjacent test will re-invent
- SSH polling, prerequisite validation, and log formatting are already implemented well in the existing
  script but are not available as reusable building blocks
- there is no standard way for CI or an agent to run "just the Hetzner dry-run" versus "just the
  Colmena command-plan check" — all scenarios live at the top level with no shared invocation surface

## Goals

1. **Reusable scenario framework** — extract the shared primitives from `tests/provision-hetzner-e2e.sh`
   into a structured `tests/lib/` library.  Any future scenario should be able to source those helpers
   rather than re-implement them.

2. **Shell-first momentum with a Go-harness seam** — implement the framework in shell now (preserving
   the current working momentum) while drawing a clear boundary at which a future Go harness can take
   over top-level orchestration without rethinking the scenario model.

3. **Scenario-driven entrypoints** — replace the current single large script pattern with thin
   `tests/scenarios/*.sh` files, one per scenario, each focused on intent and scenario-specific values.

4. **Standardised lifecycle** — all scenarios follow the same phase sequence, flag surface, and failure
   categories, making them predictable for CI pipelines, agents, and human operators.

5. **Stable run surface** — the `Justfile` becomes the single top-level entrypoint for running
   scenarios, so CI, agents, and developers all use the same invocation paths.

## Non-Goals

- **Complete backend coverage now** — wave 1 covers only currently-shipped primary paths.  Unshipped
  or partially-modelled backends (Fly, custom command backends, etc.) are not included.

- **A manifest or plugin system** — there is no scenario registry, no plugin discovery, no dynamic
  scenario loading.  The framework is a set of shell libraries and thin entrypoint scripts.

- **Forced Go migration now** — the Go harness boundary is defined as a future seam.  No Go code is
  required to implement or run wave-1 scenarios.

- **macOS / Linux parity for NixOS end-to-end paths** — scenarios that require actual NixOS builds
  (e.g. `provision-hetzner-full`) are CI/Linux first.  The framework documents this expectation rather
  than trying to paper over it.

## Architecture

The framework is a two-layer layout:

```text
tests/
  lib/                        # reusable primitives sourced by scenarios
    common.sh                 # logging, die/ok/warn/info, REPO_ROOT, tmpdir lifecycle
    sops.sh                   # SOPS binary discovery, secret extraction helpers
    ssh.sh                    # SSH key generation, socket polling, auth verification
    stackpanel_config.sh      # config.local.nix override injection and restore
    hetzner.sh                # hcloud server/key lifecycle (create, delete, ID tracking)
    deploy.sh                 # stackpanel provision/deploy invocation wrappers
    assert.sh                 # assertion helpers (exit-code checks, string contains, etc.)
  scenarios/                  # thin scenario entrypoints, one per scenario
    provision-hetzner-setup-check.sh
    provision-hetzner-dry-run.sh
    provision-hetzner-full.sh
    deploy-colmena-dry-run.sh
    deploy-nixos-rebuild-dry-run.sh
    deploy-alchemy-smoke.sh
```

### Layer responsibilities

**`tests/lib/*.sh` — primitives**

- Provide named, documented shell functions.
- Contain no scenario-specific values (server names, machine names, IP addresses, etc.).
- Are sourced by scenario scripts; they do not execute anything when sourced.
- Each file is focused on one domain (SSH, SOPS, Hetzner, etc.).
- Are validated with `bash -n` and against a short smoke test before being relied on.

**`tests/scenarios/*.sh` — thin entrypoints**

- Source the relevant `tests/lib/*.sh` helpers.
- Declare scenario-specific constants (machine name, server type, image, location, config fragments).
- Call library functions in the standard lifecycle order.
- Contain minimal decision logic — ideally none beyond the flag parsing handled by `common.sh`.
- Are readable as scenario documentation: the purpose, resources used, and expected outcomes should be
  clear from reading the scenario entrypoint alone.

**`Justfile` — top-level run surface**

- Exposes one `just` target per scenario (e.g. `just test-provision-hetzner-dry-run`).
- CI pipelines, agents, and developers all invoke scenarios through the `Justfile`.
- The `Justfile` does not embed scenario logic; it only forwards to `tests/scenarios/*.sh`.

**CI / Linux — source of truth for end-to-end NixOS paths**

- Scenarios that require real NixOS builds (full provision, nixos-rebuild) are expected to run in
  Linux CI with a full Nix builder available.
- Local macOS invocations of these scenarios document their limitations clearly (not silently pass).
- Dry-run and command-plan scenarios are designed to be safe and meaningful on macOS too.

### Go-harness seam

The current framework is intentionally shell-only.  The seam toward a future Go harness is:

- **Scenario entrypoints remain the contract** — a Go harness can call `tests/scenarios/*.sh` directly
  or re-implement them in Go using the same lifecycle phases.
- **Library functions have well-defined inputs/outputs** — no hidden global state beyond what is
  explicitly documented in each library file's header.
- **Justfile targets remain the stable invocation surface** — a Go harness can be added as a new
  Justfile target category without disturbing the existing shell-based targets.

No Go code is required in wave 1.  The seam is maintained by keeping scenario logic thin and primitive
contracts explicit so the transition can happen at the top-orchestration level only.

## Component Split

### `tests/lib/` — primitive files

| File | Responsibility |
|---|---|
| `common.sh` | `REPO_ROOT` detection, colour log helpers (`log`, `ok`, `warn`, `info`, `die`), temporary directory lifecycle, trap registration helpers, standard flag parsing (`--setup-check`, `--dry-run`, `--full`) |
| `sops.sh` | SOPS binary discovery (including direnv fallback), secret extraction by key path, token validation helpers |
| `ssh.sh` | Temporary ed25519 key pair generation, TCP port-open polling, SSH auth verification, standard SSH option sets |
| `stackpanel_config.sh` | `.stack/config.local.nix` backup, injection of a machine config block (using `lib.mkMerge` to preserve existing settings), restore on exit, create/delete when no prior file exists |
| `hetzner.sh` | `hcloud` server create/delete, SSH key register/delete, server IP extraction, server ID tracking for cleanup, ephemeral resource naming with timestamp suffix |
| `deploy.sh` | `stackpanel provision` invocation wrapper (mode-conditional flags, repo-root `cd`, exit-code capture), `stackpanel deploy` invocation wrapper with equivalent pattern |
| `assert.sh` | Exit-code assertions, string-contains assertions, file-exists assertions, standardised assertion failure output |

### `tests/scenarios/` — thin entrypoint files

| File | Scenario | Cloud resources | NixOS builder required |
|---|---|---|---|
| `provision-hetzner-setup-check.sh` | Hetzner provisioning prerequisites check | None | No |
| `provision-hetzner-dry-run.sh` | Hetzner provision dry-run (config + command plan) | CX22 server, ephemeral SSH key | No |
| `provision-hetzner-full.sh` | Hetzner full end-to-end provision via nixos-anywhere | CX22 server, ephemeral SSH key | Yes (Linux CI) |
| `deploy-colmena-dry-run.sh` | Colmena deploy command-plan validation (--dry-run) | None | Depends on flake output availability |
| `deploy-nixos-rebuild-dry-run.sh` | nixos-rebuild deploy command-plan validation (--dry-run) | None | Depends on flake output availability |
| `deploy-alchemy-smoke.sh` | Alchemy hosted deploy smoke test | None (uses existing credentials) | No |

## Wave-1 Scenario Matrix

Wave 1 covers the currently-shipped primary paths only.  Each scenario is labelled by how deep the
execution goes and whether it is safe in CI without a Linux Nix builder.

### Provisioning scenarios

| Scenario | What it tests | Cloud spend | Safe on macOS |
|---|---|---|---|
| **Hetzner setup-check** | Prerequisites (tools, SOPS, token validity) only — no cloud resources created | None | ✓ |
| **Hetzner dry-run** | Full server lifecycle (create → SSH verify → `stackpanel provision --dry-run` → delete); exercises config loading, machine lookup, target resolution, and command plan | ~1–3 minute CX22 | ✓ if prerequisites met |
| **Hetzner full** | Complete end-to-end provision including `nixos-anywhere`; requires `nixosConfigurations.ephemeral-provision-test` in the flake and a Linux Nix builder | ~5–15 minute CX22 | ✗ — Linux CI only |

The **dry-run** scenario is the standard regression mode safe to run in CI.  The **full** scenario is
reserved for scheduled or release-gating Linux CI runs.

### Deployment scenarios

| Scenario | What it tests | Exit if backend unavailable | Safe on macOS |
|---|---|---|---|
| **Colmena dry-run** | `stackpanel deploy --dry-run` against a configured colmena target; validates command-plan output without applying changes | Yes, with clear message | ✓ if Nix flake eval succeeds |
| **nixos-rebuild dry-run** | `stackpanel deploy --dry-run` against a configured nixos-rebuild target; validates command-plan output | Yes, with clear message | ✓ if Nix flake eval succeeds |
| **Alchemy smoke** | `stackpanel deploy` against the Alchemy hosted backend; validates credential availability and basic deploy path | Yes, with clear message | ✓ if credentials present |

## Standard Scenario Lifecycle

All scenarios follow five phases in order.  Phases run to completion; failures in any phase trigger
cleanup before the final exit code is emitted.

```
1. prepare
2. provision/setup
3. execute
4. verify
5. cleanup
```

### Phase definitions

**1. prepare**

- Parse flags (`--setup-check`, `--dry-run`, `--full`).
- Validate prerequisites (required tools in PATH, SOPS access, tokens, existing config state).
- Set up the cleanup trap (sourced from `common.sh`).
- Generate ephemeral resource identifiers (timestamp suffix, temp dir).

Setup-check mode exits after this phase with exit code `0` if all prerequisites are met.

**2. provision/setup**

- Create any cloud resources required by the scenario (Hetzner server, SSH key registration).
- Inject any config overrides (`.stack/config.local.nix` mutation via `stackpanel_config.sh`).
- Wait for resources to become available (SSH port polling via `ssh.sh`).

Not all scenarios have a provision/setup phase (e.g., dry-run deployment scenarios skip cloud resource
creation entirely).

**3. execute**

- Invoke the primary subject under test (`stackpanel provision`, `stackpanel deploy`, or equivalent).
- Capture exit code and output.
- Apply mode-appropriate flags (`--dry-run`, `--no-hardware-config`, etc.).

**4. verify**

- Assert expected outcomes using `assert.sh` helpers (exit code, output content, state files).
- Capture observed behaviour for debugging if assertions fail.

**5. cleanup**

- Delete cloud resources created in phase 2 (best-effort; warn on failure rather than re-failing).
- Restore config overrides to pre-test state (backup restore or file deletion).
- Remove temporary files and directories.
- Emit final pass/fail line and exit with the captured exit code.

Cleanup always runs, even when earlier phases fail.  The cleanup trap is registered in `common.sh`
before any mutating action.

## Standard Flags

All scenarios accept the same top-level flag set:

| Flag | Phase reached | Cloud resources created | Notes |
|---|---|---|---|
| `--setup-check` | prepare only | None | Validates prerequisites; safe always |
| `--dry-run` | all phases, but CLI run with `--dry-run` | Provider-dependent (Hetzner creates server; deploy scenarios do not) | Default for regression CI |
| `--full` | all phases, full execution | Provider-dependent | Linux CI only for NixOS provision |
| _(no flag)_ | same as `--dry-run` | Same as `--dry-run` | Default behaviour |
| `-h`, `--help` | — | None | Print usage and exit |

The `common.sh` library handles flag parsing and exports `SCENARIO_MODE` (`setup-check`, `dry-run`,
or `full`) for use by the rest of the scenario.

## Standard Failure Categories

Failures are classified into four categories for consistent error reporting and cleanup behaviour.

| Category | When it occurs | Cleanup triggered | Exit code |
|---|---|---|---|
| **Prerequisite failure** | A required tool, secret, or token is missing during the prepare phase | Yes (cleanup trap fires, but nothing to clean up) | `1` |
| **Execution failure** | The CLI command under test exits non-zero | Yes (cloud resources deleted, config restored) | `1` |
| **Verification failure** | An `assert.sh` assertion fails after a successful CLI run | Yes (cloud resources deleted, config restored) | `1` |
| **Cleanup failure** | A resource deletion or config restore fails during the cleanup phase | Continued (best-effort; remaining cleanup steps run) | Inherits prior exit code; warning emitted |

Cleanup failures emit a `warn` line with manual recovery instructions (e.g., `hcloud server delete
<ID>`).  They do not override a passing test exit code, but they do not suppress a failing one either.

## Migration Strategy

The migration from `tests/provision-hetzner-e2e.sh` to the framework proceeds in four steps.

### Step 1: Extract shared primitives

Move the following from `provision-hetzner-e2e.sh` into `tests/lib/`:

| Current location in the script | Target library file |
|---|---|
| Colour helpers, `log`, `ok`, `warn`, `info`, `die` functions | `common.sh` |
| SOPS binary discovery and `HCLOUD_TOKEN` extraction | `sops.sh` |
| SSH key generation, TCP polling loop, `ssh` auth verification | `ssh.sh` |
| `config.local.nix` backup, injection, and restore in the cleanup trap | `stackpanel_config.sh` |
| `hcloud server create/delete`, `hcloud ssh-key create/delete`, server IP extraction | `hetzner.sh` |
| `stackpanel provision` invocation and flag construction | `deploy.sh` |

The extraction must preserve current behaviour exactly — no semantic changes during extraction.
After extraction, `provision-hetzner-e2e.sh` can be turned into a thin wrapper that sources the new
libraries and calls the same functions in the same order, or it can be retired by pointing CI and the
Justfile at the new scenario entrypoints.

### Step 2: Rebuild Hetzner regression as thin scenarios

Create the three Hetzner scenario files:

- `tests/scenarios/provision-hetzner-setup-check.sh` — sources `common.sh`, `sops.sh`, exits after prepare phase
- `tests/scenarios/provision-hetzner-dry-run.sh` — the standard regression path; sources all relevant libs and runs through all five phases with `--dry-run`
- `tests/scenarios/provision-hetzner-full.sh` — sources the same libs; passes `--full` to `deploy.sh` invocation; documents Linux CI requirement prominently

Each scenario file should be readable without referencing the library source.

### Step 3: Add Justfile targets and wire CI

Add stable `just` targets that invoke the new scenario entrypoints.  CI configuration should be
updated to reference `just test-provision-hetzner-dry-run` rather than the legacy script path.

### Step 4: Add deployment scenarios

Add the three deployment scenarios from the wave-1 matrix using the `deploy.sh` primitives:

- `deploy-colmena-dry-run.sh`
- `deploy-nixos-rebuild-dry-run.sh`
- `deploy-alchemy-smoke.sh`

These scenarios reuse the same primitives, demonstrating that the framework generalises beyond
Hetzner provisioning.

### Legacy script disposition

`tests/provision-hetzner-e2e.sh` can either:

- **Become a thin wrapper** that sources the new libraries and calls them in order, preserving any
  existing invocation paths unchanged.
- **Be retired** after CI and the Justfile are updated to use the new scenarios.

The choice is implementation-time; either is acceptable.  The critical constraint is that the existing
regression coverage must not decrease during migration.

## Verification Strategy

Framework verification is split into two concerns.

### Framework integrity

Verifies that the library and scenario infrastructure itself is correct, independent of any
particular deployment path.

- `bash -n tests/lib/*.sh tests/scenarios/*.sh` — syntax check all files
- Cleanup/restore correctness: after a scenario run (pass or fail), verify that the config override is
  fully restored and that no cloud resources are left dangling
- Idempotent re-run: a scenario that passes once should pass again on a clean run
- Trap correctness: simulate a mid-scenario failure and confirm cleanup fires as expected

### Scenario correctness

Verifies that the scenario exercises the actual subject (the CLI command) correctly.

- **Setup-check** scenarios: verify that prerequisite checking catches known-missing tools and exits
  cleanly without creating resources
- **Dry-run** scenarios: verify that the CLI `--dry-run` output reflects the expected command plan
  (spot-check key fields using `assert.sh`)
- **Full** scenarios: verify that the provision or deploy operation completes end-to-end; run in Linux
  CI only

### CI / Linux first for NixOS paths

Scenarios that require `nix build` with a `nixosConfigurations` output (full provision, nixos-rebuild)
must document clearly that they are not expected to pass on macOS.  They should exit early with an
informative message rather than silently failing with a Nix build error.

## Guardrails

The following constraints must be preserved as the framework evolves.

**No regressions to giant one-off scripts**

New provider coverage must be added through the `tests/lib/` + `tests/scenarios/` layout.  Copy-paste
of the whole `provision-hetzner-e2e.sh` pattern is not an acceptable approach for the next scenario.
If a scenario needs a helper that does not yet exist in `tests/lib/`, the helper should be added there
rather than embedded in the scenario.

**No over-claiming partial backends**

Scenarios for backends that are only partially implemented in the CLI (e.g. Fly) must not be added to
wave 1.  A scenario that claims to test `stackpanel deploy --backend fly` while the CLI immediately
returns "unsupported" is misleading.  Add scenarios only for shipped paths.

**Preserve `.stack/hardware` wording in `docs/design/provisioning.md`**

The mention of `.stack/hardware` in `docs/design/provisioning.md` is an intentional editorial
choice.  This spec and any implementation work derived from it must not modify that document —
not the path wording, not the section structure, not any other content.  That document is a
historical reference and its exact wording is preserved by convention.

**Dry-run and full semantics must not diverge between scenarios**

The `--dry-run` flag means the same thing in every scenario: the CLI subject is invoked with its own
`--dry-run` flag, and no irreversible infrastructure changes are made.  Cloud resource creation for
target setup (Hetzner server) is still allowed in dry-run mode because it is a test fixture, not the
subject under test.  Do not repurpose `--dry-run` to mean "skip cloud resources entirely" in some
scenarios — that is `--setup-check`.

**Library contracts must be explicit**

Each library file must document its public functions, expected inputs, and any global state it sets.
Hidden side-effects between library files are not acceptable.  The goal is that a future Go harness
can reason about each library's contract without reading the full implementation.

## Success Criteria

This framework is considered successful when:

1. **Hetzner regression refactored** — `provision-hetzner-setup-check.sh`, `provision-hetzner-dry-run.sh`,
   and `provision-hetzner-full.sh` exist as thin scenario entrypoints backed by shared `tests/lib/`
   primitives.  The legacy `provision-hetzner-e2e.sh` is either a thin wrapper or retired.

2. **At least one additional shipped-path scenario uses the framework** — one of the deployment
   scenarios (`deploy-colmena-dry-run.sh`, `deploy-nixos-rebuild-dry-run.sh`, or
   `deploy-alchemy-smoke.sh`) is implemented using the shared libraries, demonstrating that the
   framework generalises beyond Hetzner provisioning.

3. **Thin, readable scenario entrypoints** — each scenario file in `tests/scenarios/` is short
   enough to read as documentation of what the scenario does, without needing to read the library
   source to understand the scenario intent.

4. **Stable run surface** — `just test-provision-hetzner-dry-run` (and equivalent targets) work
   predictably in both CI and local invocations.  Any scenario that cannot run locally (Linux CI
   only) documents this clearly and exits with an informative error rather than silently failing.

5. **No dangling resources** — all cloud resources created by any scenario are cleaned up on both
   pass and fail paths.  Manual cleanup instructions are emitted as warnings for any resource that
   cannot be deleted automatically.
