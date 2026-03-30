# Provider Scenario Testing Framework Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and verify a reusable scenario-driven test framework for deployed Stackpanel provision/deploy paths, replacing the existing single monolithic Hetzner regression script with a structured `tests/lib/` + `tests/scenarios/` layout.

**Architecture:** Seven shared shell helper modules in `tests/lib/` extracted from the existing `tests/provision-hetzner-e2e.sh`; six thin scenario entrypoints under `tests/scenarios/`; the existing Hetzner script becomes a backwards-compatible wrapper; Justfile gains a `test-scenario` dispatch recipe and group runners.

**Tech Stack:** Bash (sh-strict: `set -euo pipefail`), `hcloud` CLI (Hetzner Cloud), `stackpanel` CLI, SOPS/AGE for secret loading, `colmena`/`nixos-rebuild`/`bun` per-scenario CLI deps. CI/Linux is the source of truth for full provision paths.

**Spec:** `docs/superpowers/specs/2026-03-30-provider-scenario-testing-framework-design.md`

---

## File map

### Create
- `tests/lib/common.sh` — strict mode, REPO_ROOT, colours, log/ok/warn/info/die, require_command, register_cleanup/run_cleanups
- `tests/lib/sops.sh` — find_sops_bin, validate_sops_file, sops_load_key
- `tests/lib/ssh.sh` — wait_for_ssh, build_ssh_opts, verify_ssh_auth
- `tests/lib/stackpanel_config.sh` — inject_machine_config, restore_machine_config
- `tests/lib/hetzner.sh` — hetzner_require_token, hetzner_validate_token, hetzner_create_ssh_key, hetzner_delete_ssh_key, hetzner_create_server, hetzner_delete_server, hetzner_server_ip
- `tests/lib/deploy.sh` — run_stackpanel_provision, run_stackpanel_deploy, run_alchemy_deploy
- `tests/lib/assert.sh` — fail, assert_exit_code, assert_file_exists, assert_json_field, assert_output_contains
- `tests/scenarios/provision-hetzner-setup-check.sh`
- `tests/scenarios/provision-hetzner-dry-run.sh`
- `tests/scenarios/provision-hetzner-full.sh`
- `tests/scenarios/deploy-colmena-dry-run.sh`
- `tests/scenarios/deploy-nixos-rebuild-dry-run.sh`
- `tests/scenarios/deploy-alchemy-smoke.sh`
- `docs/superpowers/specs/2026-03-30-provider-scenario-testing-framework-design.md` (spec — companion to this plan)

### Modify
- `tests/provision-hetzner-e2e.sh` — add backwards-compat header note (body unchanged)
- `Justfile` — add `test-scenario`, `test-scenarios-safe`, `test-scenarios-provision` recipes

---

## Task 1: Extract shared shell primitives into tests/lib/

**Files:**
- Create: `tests/lib/common.sh`
- Create: `tests/lib/sops.sh`
- Create: `tests/lib/ssh.sh`
- Create: `tests/lib/stackpanel_config.sh`
- Create: `tests/lib/hetzner.sh`
- Create: `tests/lib/deploy.sh`
- Create: `tests/lib/assert.sh`

- [ ] **Step 1: Create tests/lib/common.sh**

  Must include:
  - `set -euo pipefail`
  - `REPO_ROOT` detection (skip if already set, derive from `$(BASH_SOURCE[0])/../../`)
  - Colour variables: `RED GREEN YELLOW BLUE BOLD NC`
  - Functions (all exported via `export -f`):
    - `log()` — blue bold heading
    - `ok()` — green tick
    - `warn()` — yellow warning
    - `info()` — plain
    - `die()` — red fatal + exit 1
    - `require_command <cmd> [hint]`
    - `register_cleanup <cmd>` — append to `_CLEANUP_CMDS[]`
    - `run_cleanups` — LIFO drain of `_CLEANUP_CMDS`, emit pass/fail summary

- [ ] **Step 2: Create remaining lib files** (sops, ssh, stackpanel_config, hetzner, deploy, assert) following the function contracts in the spec

- [ ] **Step 3: Verify bash -n for all lib files**

  ```bash
  for f in tests/lib/*.sh; do bash -n "$f" && echo "OK: $f" || echo "FAIL: $f"; done
  ```
  Expected: all print `OK`.

- [ ] **Step 4: Commit**

  ```bash
  git add tests/lib/
  git commit -m "feat: add tests/lib framework primitives (common, sops, ssh, config, hetzner, deploy, assert)"
  ```

---

## Task 2: Create thin scenario entrypoints in tests/scenarios/

**Files:**
- Create: `tests/scenarios/provision-hetzner-setup-check.sh`
- Create: `tests/scenarios/provision-hetzner-dry-run.sh`
- Create: `tests/scenarios/provision-hetzner-full.sh`
- Create: `tests/scenarios/deploy-colmena-dry-run.sh`
- Create: `tests/scenarios/deploy-nixos-rebuild-dry-run.sh`
- Create: `tests/scenarios/deploy-alchemy-smoke.sh`

Each scenario must:
- Set `REPO_ROOT` before sourcing any lib
- Source only the libs it needs
- Register cleanup via `register_cleanup` + `trap run_cleanups EXIT`
- Follow the lifecycle: prepare → provision/setup → execute → verify → cleanup

- [ ] **Step 1: Create provision-hetzner-setup-check.sh**
  Sources: common.sh, sops.sh. Validates tools, SOPS file, loads HCLOUD_TOKEN, validates against API, prints setup-check passed.

- [ ] **Step 2: Create provision-hetzner-dry-run.sh**
  Sources all libs. Creates CX22, injects config, waits for SSH, runs `stackpanel provision --dry-run --no-hardware-config --install-target`, cleans up.

- [ ] **Step 3: Create provision-hetzner-full.sh**
  Same as dry-run but validates nixos-anywhere + flake config, runs full provision, verifies NixOS boot with `nixos-version`.

- [ ] **Step 4: Create deploy-colmena-dry-run.sh**
  Sources common, deploy, assert. Auto-detects or accepts `STACKPANEL_COLMENA_TEST_APP`. Skips (not fails) if no app configured. Runs `stackpanel deploy <app> --dry-run`.

- [ ] **Step 5: Create deploy-nixos-rebuild-dry-run.sh**
  Same pattern as colmena but for nixos-rebuild backend. Accepts `STACKPANEL_NIXOS_REBUILD_TEST_APP`.

- [ ] **Step 6: Create deploy-alchemy-smoke.sh**
  Sources common, deploy, assert. Validates alchemy entrypoint file. Auto-detects or accepts `STACKPANEL_ALCHEMY_TEST_APP`. Skips (not fails) if no app or entrypoint. Runs `stackpanel deploy <app> --dry-run`.

- [ ] **Step 7: Verify bash -n for all scenario files**

  ```bash
  for f in tests/scenarios/*.sh; do bash -n "$f" && echo "OK: $f" || echo "FAIL: $f"; done
  ```
  Expected: all print `OK`.

- [ ] **Step 8: Commit**

  ```bash
  git add tests/scenarios/
  git commit -m "feat: add tests/scenarios framework entrypoints (6 scenarios)"
  ```

---

## Task 3: Update provision-hetzner-e2e.sh and Justfile

**Files:**
- Modify: `tests/provision-hetzner-e2e.sh`
- Modify: `Justfile`

- [ ] **Step 1: Add backwards-compat header to provision-hetzner-e2e.sh**

  At the top of the existing header comment block, add a note that this is a compatibility wrapper that delegates to `tests/scenarios/` and that new tests should use the scenario scripts directly. The body of the script is unchanged.

- [ ] **Step 2: Update Justfile**

  After the existing `test-provision-hetzner-setup-check` recipe, add:
  ```just
  # ── Scenario tests (provision/deploy framework) ─────────────────────────────

  test-scenario name *args:
      {{ nix-run }}bash "{{ rootdir }}/tests/scenarios/{{ name }}.sh" {{ args }}

  test-scenarios-safe:
      # colmena dry-run, nixos-rebuild dry-run, alchemy smoke
      ...

  test-scenarios-provision:
      # setup-check then dry-run
      ...
  ```

- [ ] **Step 3: Commit**

  ```bash
  git add tests/provision-hetzner-e2e.sh Justfile
  git commit -m "feat: update Justfile + provision-hetzner-e2e.sh for scenario framework"
  ```

---

## Task 4: Write the spec document

**Files:**
- Create: `docs/superpowers/specs/2026-03-30-provider-scenario-testing-framework-design.md`

- [ ] **Step 1: Write spec covering all 13 approved sections**

  See `~/.mux/plans/stackpanel/deployment-88x3.md` for the full section list.

- [ ] **Step 2: Verify the spec does not modify docs/design/provisioning.md**

  This file has an intentional `.stack/hardware` wording that must not be changed.

- [ ] **Step 3: Commit**

  ```bash
  git add docs/superpowers/specs/2026-03-30-provider-scenario-testing-framework-design.md
  git commit -m "docs: add provider scenario testing framework spec"
  ```

---

## Task 5: Run and verify safe scenarios

- [ ] **Step 1: Run bash -n on everything**

  ```bash
  for f in tests/lib/*.sh tests/scenarios/*.sh; do
    bash -n "$f" && echo "OK: $f" || echo "FAIL: $f"
  done
  ```
  Expected: all `OK`.

- [ ] **Step 2: Run the safe scenarios (no cloud, no credentials needed)**

  ```bash
  bash tests/scenarios/deploy-colmena-dry-run.sh
  bash tests/scenarios/deploy-nixos-rebuild-dry-run.sh
  bash tests/scenarios/deploy-alchemy-smoke.sh
  ```

  Expected: each scenario either completes cleanly (if an app is configured) or prints a `warn` + `Skipping scenario` message and exits 0.

- [ ] **Step 3: Verify Justfile recipes parse**

  ```bash
  just --list | grep test-scenario
  ```
  Expected: `test-scenario`, `test-scenarios-safe`, `test-scenarios-provision` appear.

- [ ] **Step 4: Run test-scenarios-safe via Justfile**

  ```bash
  NIX_SKIP_DEVELOP=1 just test-scenarios-safe
  ```
  Expected: all three deploy scenarios exit 0.

---

## Validation

At the end of all tasks:

- [ ] All `tests/lib/*.sh` pass `bash -n`
- [ ] All `tests/scenarios/*.sh` pass `bash -n`
- [ ] `just --list` shows the new recipes
- [ ] `just test-scenarios-safe` exits 0
- [ ] No dangling resources (`hcloud server list` shows no `stackpanel-e2e-*` entries)
- [ ] `docs/design/provisioning.md` is unchanged

## Guardrails

- Do NOT modify `docs/design/provisioning.md` — it has an intentional `.stack/hardware` wording.
- Do NOT remove or break existing `tests/provision-hetzner-e2e.sh` behaviour.
- Scenario scripts should skip (exit 0) rather than fail when a provider/app is not configured in the current environment.
- Dry-run and setup-check scenarios must not create any cloud resources.
