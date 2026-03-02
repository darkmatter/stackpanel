# Alchemy Module

Centralized Alchemy IaC module for stackpanel.

This module provides:

- Shared Alchemy configuration under `stackpanel.alchemy.*`
- Generated `@gen/alchemy` package (`createApp`, state store factory, helpers)
- First-run Cloudflare setup script (`alchemy:setup`)
- One-command deploy wrapper (`deploy`)
- Optional bootstrap flow to solve Cloudflare state-store chicken-and-egg

## Files

- `default.nix` - module entrypoint (imports options + codegen)
- `options.nix` - option schema for `stackpanel.alchemy.*`
- `codegen.nix` - generates package files/scripts and wires devshell env
- `templates/` - TypeScript and shell templates used by codegen

## Core Options

```nix
stackpanel.alchemy = {
  enable = true;

  # Shared app defaults
  app-name = "my-project";
  stage = null;

  # State store for alchemy state
  state-store.provider = "auto"; # cloudflare | filesystem | auto

  # Deploy DX
  deploy = {
    enable = true;
    token-scopes = "profile"; # profile | god
    auto-provision-state-store = true;
    run-file = "alchemy.run.ts";
  };
};
```

## Secrets Integration

When these paths are set, values are injected into the devshell environment:

```nix
stackpanel.alchemy.secrets = {
  cloudflare-token-sops-path = "ref+sops://.stackpanel/secrets/vars/common.sops.yaml#/cloudflare-api-token";
  state-token-sops-path = "ref+sops://.stackpanel/secrets/vars/common.sops.yaml#/alchemy-state-token";
  sops-group = "common";
};
```

## Generated Scripts

When `stackpanel.alchemy.deploy.enable = true`:

- `alchemy:setup`
  - Runs `alchemy configure` + `alchemy login`
  - Creates Cloudflare token via `alchemy util create-cloudflare-token`
  - Generates `ALCHEMY_STATE_TOKEN`
  - Stores both tokens via `secrets:set`
  - Optionally bootstraps Cloudflare state store worker

- `deploy`
  - Loads tokens from env/secrets
  - Auto-runs `alchemy:setup` if Cloudflare is not configured
  - Executes `bunx alchemy deploy <run-file> --stage <stage>`

## Bootstrap State Store

If `deploy.auto-provision-state-store = true`, codegen emits:

- `packages/gen/alchemy/bootstrap.run.ts`

`alchemy:setup` uses that file to provision and verify `CloudflareStateStore`
with filesystem-backed state first, then normal deploys use shared Cloudflare
state.

## Typical Usage

```bash
nix develop --impure
deploy staging
```

First run triggers setup automatically; later runs go straight to deploy.
