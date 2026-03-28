# Deployment System

> **Canonical specification:** This document is the authoritative deployment-system spec for Stackpanel maintainers and agents.
>
> **Supersedes:**
> - `docs/design/deploy-command.md`
> - `docs/design/provisioning.md`
>
> Those documents remain useful as historical rationale, but they are no longer the source of truth.

## Problem

Stackpanel’s deployment story is currently spread across multiple layers of documentation:

- design-era drafts in `docs/design/`
- public deployment guides under `apps/docs/content/docs/deployment/`
- CLI behavior in `apps/stackpanel-go/cmd/cli/{deploy,provision}.go`
- Nix-side deployment contracts in `nix/stackpanel/modules/deploy/` and `nix/stackpanel/lib/deploy.nix`
- Studio UI work in `apps/web/src/components/studio/panels/deploy/`

That fragmentation makes it too easy to confuse:

- design intent with shipped behavior
- public how-to guides with internal architecture contracts
- provisioning with deployment
- provider-specific hosted flows with the primary NixOS machine workflow

This specification defines the canonical model that ties those pieces together.

## Goals

- Define one authoritative deployment-system specification.
- Separate **deployment** from **provisioning**.
- Describe the current Nix-side, CLI-side, and docs-side contracts.
- Preserve the valid architecture reasoning from the older design docs.
- Clearly distinguish **implemented now**, **partially implemented**, and **future work**.
- Clarify which documentation entrypoints are canonical versus secondary.

## Non-Goals

- Replacing public provider guides with internal architecture prose.
- Declaring unfinished deploy UX as already shipped.
- Folding all build-pipeline design work into this document.
- Superseding `docs/design/app-derivations.md` unless the app-build contract is later explicitly merged into this spec.

## Canonical Scope

This document covers the deployment system as a whole:

1. **Provisioning machines** into deployable NixOS hosts.
2. **Deploying apps** onto configured targets.
3. **Computing deployable artifacts and host configs** from Stackpanel’s Nix configuration.
4. **Recording deploy/provision state** for operator visibility.
5. **Explaining the relationship** between the Nix layer, CLI layer, Studio UI, and public docs.

## Core Terms

| Term | Meaning |
|---|---|
| **Provisioning** | Installing or re-installing a target machine so it becomes a deployable NixOS host. |
| **Deployment** | Shipping an app or system update onto existing infrastructure. |
| **Machine inventory** | The configured set of deploy targets, primarily from `stackpanel.deployment.machines`. |
| **Hosted backend** | A provider-specific deployment flow such as Cloudflare/Alchemy or Fly, rather than a NixOS machine target. |
| **Canonical spec** | This document; the maintainer/agent source of truth for deployment architecture and contracts. |

## System Model

Stackpanel’s deployment system is centered on the idea that **Nix outputs are the canonical deployment contract for machine-based deployments**.

At a high level:

```text
.stack/config.nix
  -> stackpanel module evaluation
  -> deployment options + machine inventory + app deploy config
  -> flake outputs (nixosModules, nixosConfigurations, colmenaHive)
  -> CLI workflows (stackpanel provision, stackpanel deploy)
  -> local state files and operator-facing status
```

### Primary Linux-host path

For Linux hosts, the primary path is:

- provision with `nixos-anywhere`-based workflows
- deploy with `colmena` or `nixos-rebuild`
- derive machine/system configuration from flake outputs

This is the most general Stackpanel deployment model for software that can run as a Linux process.

### Hosted exceptions / adapters

Hosted backends remain valid, but they are not equivalent to the NixOS machine path:

- **Cloudflare / Alchemy** for Worker-style deployments that cannot run as NixOS services
- **Fly** for container-oriented deployments

These flows exist alongside the NixOS path. They do not replace the NixOS deployment model as the primary machine/server story.

## Deployment vs Provisioning

Deployment and provisioning are distinct operations and must stay distinct in both docs and UX.

| Operation | Primary tool path | Effect |
|---|---|---|
| **Provisioning** | `stackpanel provision` -> `nixos-anywhere` workflows | Creates or re-creates a deployable NixOS host |
| **Deployment** | `stackpanel deploy` -> `colmena`, `nixos-rebuild`, or hosted backend adapter | Pushes an app/system update to existing infrastructure |

### Provisioning contract

The current provisioning contract is implemented in `apps/stackpanel-go/cmd/cli/provision.go`.

The shipped command contract includes:

- `stackpanel provision` with no args lists configured machines and provisioning status
- `stackpanel provision <machine>` provisions a configured machine
- `--install-target` overrides the install-time host/IP
- `--format` opts into disko-backed disk formatting
- `--no-hardware-config` skips hardware-config generation
- `--dry-run` prints commands instead of executing
- `--reprovision` is required for destructive re-provisioning of an already provisioned machine

Provisioning writes local state to `.stack/state/machines.json` and can generate machine files under `.stack/machines/<machine>/`.

### Deployment contract

The current deployment contract is implemented in `apps/stackpanel-go/cmd/cli/deploy.go`.

The shipped command contract currently includes:

- `stackpanel deploy` with no args lists configured machines and deployable apps
- `stackpanel deploy <app>` deploys a single configured app
- `stackpanel deploy status [app]` reads recorded deployment history from `.stack/state/deployments.json`
- `--dry-run` prints the command that would be run

The deploy command currently resolves app config from live Nix evaluation rather than the state file.

## Nix-Side Contracts

The Nix deployment layer is defined primarily by:

- `nix/stackpanel/modules/deploy/module.nix`
- `nix/stackpanel/lib/deploy.nix`
- `nix/flake/global-outputs.nix`

### App deployment options

`nix/stackpanel/modules/deploy/module.nix` extends per-app deployment config with:

- `deployment.backend`
- `deployment.targets`
- `deployment.defaultEnv`
- `deployment.nixosModule`
- `deployment.command`
- `deployment.modules`

It also defines the machine inventory under:

- `stackpanel.deployment.machines`

### Machine inventory contract

`stackpanel.deployment.machines` is the canonical machine-target definition used by the deploy/provision CLI path.

Key machine fields include:

- `host`
- `user`
- `sshPort`
- `proxyJump`
- `system`
- `hardwareConfig`
- `diskLayout`
- `modules`
- `authorizedKeys`

### Flake outputs

`nix/flake/global-outputs.nix` publishes the machine-deployment outputs:

- `nixosModules`
- `nixosConfigurations`
- `colmenaHive`

`nix/stackpanel/lib/deploy.nix` computes those outputs from the configured apps and machines.

Important behavior in the current implementation:

- machine-app assignment is driven by `deployment.targets`
- machine modules include app modules, disk layout, hardware config, authorized keys, and extra modules
- unprovisioned machines receive a stub filesystem / boot configuration so flake evaluation can still succeed before first provision

## State Files

The CLI persists local operator state in gitignored files under `.stack/state/`.

### Provisioning state

`apps/stackpanel-go/cmd/cli/machine_state.go` stores provisioning metadata in:

- `.stack/state/machines.json`

This includes:

- provision timestamp
- install target
- whether hardware config was generated
- hardware config path
- nix revision

### Deployment state

`apps/stackpanel-go/cmd/cli/deploy.go` stores deploy metadata in:

- `.stack/state/deployments.json`

This includes:

- timestamp
- backend
- target
- nix revision

These state files are local operational records, not the source of truth for configuration.

## Backend Model

### Canonical backend maturity model

| Backend path | Role in the system | Current status |
|---|---|---|
| `colmena` | Primary multi-host NixOS deployment backend | **Implemented** |
| `nixos-rebuild` | Primary single-host NixOS deployment backend | **Implemented** |
| `alchemy` | Hosted Cloudflare adapter | **Partially implemented in CLI; broader provider flow also documented elsewhere** |
| `fly` | Hosted container adapter | **Modeled in config/docs; not fully wired through the deploy CLI** |
| `custom` | Escape hatch for custom deploy commands | **Option exists; end-to-end contract remains implementation-dependent** |

### Hosted backend guidance

Hosted backends are still part of the deployment story, but the canonical system spec treats them as specialized flows:

- public provider guides remain under `apps/docs/content/docs/deployment/`
- provider-specific module docs remain useful as reference material
- this spec defines how they fit into the overall model, not every provider detail

## Current Status Matrix

This section is intentionally reality-grounded.

| Area | Status | Notes |
|---|---|---|
| `stackpanel provision` core workflow | **Implemented** | Includes listing, kexec path, disko path, dry run, hardware-config generation, and re-provision guard |
| machine state tracking | **Implemented** | `.stack/state/machines.json` |
| `stackpanel deploy` app deploy path | **Implemented for machine-oriented app deploys** | Single-app entrypoint and deploy-status recording exist |
| machine-aware deploy listing | **Implemented, but still basic** | Command lists machines and deployments; richer targeting/reporting remains future work |
| `colmena` backend dispatch | **Implemented** | Main NixOS multi-host backend |
| `nixos-rebuild` backend dispatch | **Implemented** | Single-host NixOS backend |
| `alchemy` backend dispatch | **Partially implemented** | Minimal CLI path exists; broader hosted flow remains separate from the NixOS machine story |
| `fly` backend dispatch | **Not fully implemented in CLI** | Backend is modeled, but current CLI fallback still reports unsupported behavior |
| Studio Deploy panel as full contract surface | **Partial** | Existing panel work is meaningful, but this spec remains authoritative over current UI coverage |
| public deployment docs alignment | **Partial** | Provider guides exist, but they are not the canonical architecture/system contract |

## UI and Documentation Contract

### Studio UI

The Studio Deploy panel is an operator surface, not the canonical definition of the deployment system.

It should reflect the same underlying contracts defined here, especially around:

- machine inventory
- deploy/provision state
- app-to-machine targeting
- backend-specific deploy actions

When UI behavior differs from this spec, the UI should be treated as incomplete rather than this spec being inferred from the UI.

### Documentation layers

The deployment docs now have a clear hierarchy:

1. **Canonical maintainer/agent spec**
   - `docs/superpowers/specs/2026-03-28-deployment-system.md`
2. **Public user/operator guides**
   - `apps/docs/content/docs/deployment/*`
3. **Auto-generated CLI reference**
   - docs generated from the Cobra commands
4. **Historical design rationale**
   - `docs/design/deploy-command.md`
   - `docs/design/provisioning.md`

Public docs should summarize workflows and point back to this canonical spec for architecture/contracts, rather than restating the full system design.

## Related but Not Superseded

The following docs remain related, but are not superseded by this spec:

- public provider guides under `apps/docs/content/docs/deployment/`
- `docs/design/app-derivations.md`
- provider/module READMEs that document hosted backend details

## Acceptance Criteria for Adopting This Spec

This specification is considered adopted when:

- this file is treated as the canonical deployment-system reference
- `docs/design/deploy-command.md` and `docs/design/provisioning.md` are explicitly marked superseded
- deployment entrypoint docs point readers here for architecture/contracts
- public docs remain task-oriented rather than becoming competing architecture specs
- future deployment work describes gaps as **planned** until the implementation actually ships

## Superseded Documents

This document supersedes:

- `docs/design/deploy-command.md`
- `docs/design/provisioning.md`

Those files may still be kept for historical context, but any conflict must be resolved in favor of this specification.
