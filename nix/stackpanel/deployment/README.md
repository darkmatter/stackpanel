# Deployment Module

> **Canonical specification:** `docs/superpowers/specs/2026-03-28-deployment-system.md`
>
> This README is a directory-level note for the hosted deployment helpers under `nix/stackpanel/deployment/`. It is not the canonical deployment-system spec.

## Scope of this directory

This directory contains the hosted deployment module surface for:

- shared Alchemy deployment plumbing
- Cloudflare
- AWS
- Fly.io

`stackpanel deploy` is the canonical execution path. The modules in this
directory define the hosted deployment configuration and generated helpers that
feed that CLI flow.

## For the full deployment contract, see

- `docs/superpowers/specs/2026-03-28-deployment-system.md`
- `nix/stackpanel/modules/deploy/module.nix`
- `nix/stackpanel/lib/deploy.nix`
- `apps/stackpanel-go/cmd/cli/deploy.go`
- `apps/stackpanel-go/cmd/cli/provision.go`

## Documentation hierarchy

- **Canonical maintainer/agent spec:** `docs/superpowers/specs/2026-03-28-deployment-system.md`
- **Public deployment guides:** `apps/docs/content/docs/deployment/`
- **Historical design rationale:** `docs/design/deploy-command.md`, `docs/design/provisioning.md`

If this README disagrees with the canonical deployment-system spec, follow the canonical spec.
