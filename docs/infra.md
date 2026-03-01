# Infra + Colmena Plan

This document captures the agreed plan to make Colmena the recommended deployment tool, autogenerate hive configs from infra outputs, and provide a first-class Studio UI for machines and deploy actions.

## Decisions

- Machine inventory is authoritative from infra outputs.
- Machine edits in the UI write back to infra module source via tree-sitter.
- Colmena remains the recommended default, but other deploy modules stay available.
- Generated Colmena hive files live in `.stackpanel/state/colmena` (not checked in).

## Goals

- Autogenerate Colmena hive configs from infra outputs and per-app deploy mapping.
- Provide a first-class Colmena UI in Studio (machines, targets, actions).
- Enable full-source infra module edits in the UI via tree-sitter.

## Phase 1: Data Model

1) Add per-app deploy mapping:
- `stackpanel.apps.<appId>.deploy.enable`
- `stackpanel.apps.<appId>.deploy.targets` (machine ids or tags)
- `stackpanel.apps.<appId>.deploy.role`
- `stackpanel.apps.<appId>.deploy.nixosModules`
- `stackpanel.apps.<appId>.deploy.system`
- `stackpanel.apps.<appId>.deploy.secrets`

2) Add computed view:
- `stackpanel.appsComputed.<appId>.deployTargets`

3) Add Colmena machine source:
- `stackpanel.colmena.machineSource = "infra"`
- `stackpanel.colmena.machinesComputed` (read-only)

## Phase 2: Infra Outputs -> Machines

1) Standardize infra machine output schema:
- `id`, `name`, `host`, `ssh.{user,port,keyPath}`
- `tags`, `roles`, `arch`, `provider`
- `publicIp`, `privateIp`, `labels`
- `nixosProfile`, `nixosModules`

2) Require infra modules to emit `machines` output in this schema.

3) Map outputs into Colmena inventory:
- `stackpanel.colmena.machinesComputed = stackpanel.infra.outputs.machines`

## Phase 3: Colmena Hive Generation

1) Add Colmena codegen module:
- Generates `.stackpanel/state/colmena/hive.nix`
- Generates `.stackpanel/state/colmena/nodes/*.nix`

2) Bind Colmena config:
- `stackpanel.colmena.config = ".stackpanel/state/colmena/hive.nix"`

3) Make scripts use generated hive:
- `colmena-apply`, `colmena-build`, `colmena-eval`

## Phase 4: Validation + Health

- Healthchecks for missing host/ssh data
- Healthchecks for apps with deploy enabled but no resolved targets
- Optional arch/system mismatch warnings
- Add `colmena-validate` script for summary + errors

## Phase 5: Studio UI (Colmena Recommended)

1) Deploy page becomes Colmena-centric:
- Overview (machine count, unhealthy, last deploy)
- Actions (eval/build/apply + on/exclude)

2) Machines inventory view:
- Read-only list from `machinesComputed`
- "Edit Infra Module" action opens source editor (tree-sitter)

3) App-to-machine mapping:
- Per-app deploy panel for targets, role, modules
- Optional matrix view for bulk mapping

4) Keep other deploy modules, mark Colmena as recommended default.

## Phase 6: Tree-Sitter Edits

- Use tree-sitter to patch infra module source (full edits).
- After edits, prompt or auto-run `infra:deploy`.
- Refresh machine inventory after infra outputs sync.

## Phase 7: Docs + Migration

- Document machine output schema and mapping rules.
- Update deploy docs to highlight Colmena as recommended default.
- Keep Fly/Cloudflare docs intact; add migration guidance where relevant.
