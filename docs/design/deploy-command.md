# Design: `stackpanel deploy` Command

**Status:** Draft
**Date:** 2026-03-10

---

## 1. Context and Scope

Stackpanel already has fragments of deployment thinking scattered across the codebase:

- `apps.web.deployment.host = "cloudflare"` with `bindings` and `secrets` fields
- `deployment.fly.organization = "darkmatter"` at the top level
- `alchemy.run.ts` / `infra/alchemy/index.ts` for Cloudflare + Neon + Upstash provisioning
- App derivations from `nix build .#web`, `nix build .#stackpanel-go` (recent PR)
- Secrets managed via SOPS/chamber with environment scoping (`dev.yaml`, `staging.yaml`, `prod.yaml`)

The goal is a first-class `stackpanel deploy [app] [--env staging]` command that orchestrates deployment using one of several backends, with Nix derivations built by the `app-build` module as a first-class input to that process.

---

## 2. Questioning the Premise

Before designing, it is worth challenging several assumptions embedded in the task description.

### 2.1 Which backend is actually "general"?

An initial reading might rank backends by familiarity: PaaS (Fly, Cloudflare) feels familiar; NixOS-native feels specialized. This is backwards.

- **nixos-anywhere** can provision *any* bare Linux machine — Hetzner, AWS EC2, bare metal, OVH, GCP VM — into a NixOS host. After that, **colmena** or **nixos-rebuild** redeploys it.
- **Fly.io** works on Fly. **Alchemy/Cloudflare Workers** works on Cloudflare.

NixOS-native is the general Linux-server story. PaaS adapters are narrow, platform-specific cases.

This matters because Stackpanel is a Nix project. Its devenv, secrets, module system, and build pipeline are all Nix-native. The app derivations produced by the `app-build` module connect directly to a NixOS deployment without any intermediate step (no Docker build, no artifact upload). Choosing a PaaS-first architecture would mean building a Nix toolchain to produce non-Nix artifacts for non-Nix platforms — working against the grain.

The revised hierarchy:

| Domain | Primary tool | Nature |
|---|---|---|
| Linux servers (any provider) | colmena / nixos-rebuild / nixos-anywhere | **Primary** |
| Serverless edge (Cloudflare Workers) | Alchemy + Vite | Genuine exception — can't run NixOS |
| Managed PaaS (Fly.io, etc.) | fly CLI / nix2container | Adapter when you're locked in |

The Cloudflare Workers case is a genuine exception, not a typical case. V8 isolates cannot run NixOS services; Alchemy is the right tool there. But for anything that runs as a Linux process — a web server, an API, a CLI agent — NixOS is the natural deployment target.

### 2.2 "Deploy" is two orthogonal concerns

The tools mentioned (nixos-rebuild, colmena, nixos-anywhere, alchemy, terraform) span two fundamentally different operations:

| Class | Tools | Operation |
|---|---|---|
| **Infrastructure provisioning** | nixos-anywhere, terraform, alchemy (for cloud resources) | Create/modify machines, databases, DNS |
| **Service deployment** | nixos-rebuild, colmena, fly deploy | Push a new app version to running infrastructure |

These have different triggers, different state models, and different failure modes. A single `stackpanel deploy` command should own the second concern (service deployment); infrastructure provisioning is a related but separate workflow — potentially `stackpanel infra apply`.

### 2.3 What is the deployment artifact?

The answer depends on the backend:

- **NixOS targets:** the artifact is a Nix closure. The built derivation (`nix build .#stackpanel-go`) is included as a NixOS service directly. No intermediate packaging.
- **Container targets (Fly, ECS):** the artifact is an OCI image. nix2container can produce this from the same derivation — reproducibly, without a Dockerfile.
- **Cloudflare Workers:** the artifact is a JS bundle produced by Vite/Wrangler. Not a Nix derivation. Alchemy drives this build.
- **Static sites:** the artifact is a directory. Can come from `nix build .#docs` and be served by Nginx on NixOS, or pushed to Cloudflare Pages.

For NixOS backends the `app-build` derivation is a first-class, direct input. For container backends it is one step removed (derivation → OCI image via nix2container). For Cloudflare Workers it is irrelevant.

---

## 3. Architecture Overview

The proposed architecture has three layers:

```
stackpanel deploy [app] [--env prod] [--target my-server]
       │
       ▼
┌─────────────────────────────────────────┐
│  Deploy Coordinator (Go CLI)            │
│  - Reads app deployment config          │
│  - Resolves environment + secrets       │
│  - Invokes backend                      │
└─────────────────────────────────────────┘
       │
       ├── NixOS backend (colmena / nixos-rebuild)
       │      │
       │      ├── nix build .#<app>  (derivation)
       │      ├── Generate NixOS service module
       │      └── colmena apply --on <target>
       │
       ├── nixos-anywhere backend (initial provisioning only)
       │      └── nixos-anywhere --flake .#<host> root@<ip>
       │
       ├── Container backend (Fly, ECS)
       │      ├── nix build .#<app>-container (OCI via nix2container)
       │      └── fly deploy --image <image>
       │
       └── Alchemy backend (Cloudflare Workers, cloud resources)
              └── bun run alchemy.run.ts --stage prod
```

---

## 4. Detailed Design: Nix-Native Backend (Primary)

### 4.1 How apps become NixOS services

The `app-build` module produces a derivation for each app. The deploy module wraps it in a NixOS systemd service:

```nix
# Generated by stackpanel for apps.stackpanel-go
{ config, pkgs, inputs, ... }:
{
  systemd.services.stackpanel-go = {
    description = "Stackpanel CLI and agent";
    wantedBy    = [ "multi-user.target" ];
    after       = [ "network.target" "sops-nix.service" ];
    serviceConfig = {
      ExecStart      = "${inputs.self.packages.x86_64-linux.stackpanel-go}/bin/stackpanel agent";
      Restart        = "on-failure";
      User           = "stackpanel";
      EnvironmentFile = config.sops.secrets."stackpanel-go-env".path;
      # Hardening
      ProtectSystem  = "strict";
      NoNewPrivileges = true;
    };
  };

  # Secrets via sops-nix (integrates with SOPS files already in .stackpanel/secrets/)
  sops.secrets."stackpanel-go-env" = {
    sopsFile = ./secrets/prod.yaml;
    format   = "dotenv";
    owner    = "stackpanel";
  };

  users.users.stackpanel = {
    isSystemUser = true;
    group        = "stackpanel";
  };
  users.groups.stackpanel = {};
}
```

The key insight: the `ExecStart` path is `inputs.self.packages.x86_64-linux.stackpanel-go` — the flake's own output. When colmena builds the NixOS system, it evaluates the flake, builds the app derivation, and includes the closure in the system. The secrets come from the SOPS files already present in `.stackpanel/secrets/`, managed by sops-nix.

This module can be:
- **Auto-generated** at deploy time from `apps.<name>` config (lower friction)
- **Provided as a NixOS module** in `stackpanel.nixosModules.<name>` that users import into their own host config (more flexible)

Both are valuable; auto-generation for the default case, explicit import for customization.

### 4.2 Colmena hive configuration

The deployment topology lives in `.stackpanel/deploy/`:

```nix
# .stackpanel/deploy/colmena.nix  (user-authored, git-tracked)
{
  meta = {
    nixpkgs = import <nixpkgs> { system = "x86_64-linux"; };
    # Pass the flake inputs so host configs can reference self.packages
    specialArgs = { inherit inputs; };
  };

  "prod-server" = { pkgs, inputs, ... }: {
    deployment = {
      targetHost = "prod.example.com";
      targetUser = "root";
      keys."deploy_ed25519".keyFile = ~/.ssh/id_ed25519;
    };
    imports = [
      # Hardware config (nixos-anywhere generates this on first deploy)
      ./hosts/prod-server/hardware-configuration.nix
      # stackpanel-generated NixOS module for each deployed app
      inputs.self.nixosModules.stackpanel-go
      inputs.self.nixosModules.docs
    ];
  };
}
```

`stackpanel deploy` would generate (or update) `nixosModules.<name>` in the flake from `apps.<name>` config, so users don't need to write systemd services by hand.

### 4.3 Initial provisioning with nixos-anywhere

For a brand-new machine, nixos-anywhere installs NixOS from the flake:

```
stackpanel deploy provision prod-server --target root@1.2.3.4
  1. Read .stackpanel/deploy/colmena.nix → find "prod-server" host config
  2. nixos-anywhere --flake .#prod-server root@1.2.3.4
     (installs NixOS, copies secrets, activates)
  3. Record in .stackpanel/state/deployments.json: { prod-server: { provisioned: true, ... } }
```

After provisioning, subsequent deploys use colmena:

```
stackpanel deploy stackpanel-go --target prod-server
  1. nix build .#stackpanel-go (or use cache)
  2. colmena build --on prod-server
  3. colmena apply --on prod-server
```

### 4.4 Secrets at deployment time

For NixOS targets, sops-nix handles secrets natively. The SOPS files already in `.stackpanel/secrets/` are referenced in the NixOS module and decrypted at activation using the host's SSH key (agenix model) or a master key.

The deployment config declares which secrets each app needs:

```nix
apps.stackpanel-go.deployment = {
  enable = true;
  backend = "colmena";
  targets = [ "prod-server" ];
  secrets = {
    # Key in SOPS file → env var name in the running service
    "STACKPANEL_DB_URL"    = "prod/DATABASE_URL";
    "STACKPANEL_AUTH_SECRET" = "prod/AUTH_SECRET";
  };
};
```

The deploy module generates the sops-nix config from this, writing a `dotenv`-format secrets file that the systemd `EnvironmentFile` consumes.

---

## 5. Detailed Design: Alchemy Backend (Cloudflare Workers Exception)

The Cloudflare Workers case is genuinely different. Workers run in V8 isolates; they are not Linux processes and cannot be wrapped in a systemd service. Alchemy is the right tool.

`stackpanel deploy web --env prod` for a Cloudflare-hosted app maps to:

```
1. Resolve secrets for "prod" from SOPS → inject as process env
2. exec: STAGE=prod bun run alchemy.run.ts
   (Alchemy deploys CF Worker, Neon branch, Upstash Redis)
3. Record deploy metadata in .stackpanel/state/deployments.json
```

The existing `alchemy.run.ts` / `infra/alchemy/index.ts` already handles this. The `stackpanel deploy` CLI is a thin wrapper that:
- Resolves the correct `STAGE` from the `--env` flag
- Injects decrypted secrets as env vars
- Invokes Alchemy with those env vars
- Captures and surfaces the output

The key config distinction: `apps.web.deployment.backend = "alchemy"` vs `apps.stackpanel-go.deployment.backend = "colmena"`.

---

## 6. Detailed Design: Container Backend (Fly, ECS)

For apps targeting container platforms, nix2container is already configured in the project. The deploy pipeline:

```
stackpanel deploy web --backend fly --env prod
  1. nix build .#web-container  (OCI image via nix2container)
     (uses remote Linux builder if on macOS)
  2. fly secrets set --app myapp-prod \
       $(stackpanel secrets export --app web --env prod --format fly)
  3. fly deploy --app myapp-prod --image <store path>
```

The Nix derivation from `app-build` is the input to nix2container; the container image inherits all the closure guarantees. The image reference is a Nix store path — content-addressed and reproducible.

**macOS caveat:** nix2container requires Linux. A preflight check should verify the remote Linux builder is reachable before attempting a container build. The builder is already configured in `config.nix` (Tailscale IP + SSH key).

---

## 7. Config Schema

### 7.1 Per-app deployment options

A new `deploy/schema.nix` (parallel to `app-build/schema.nix`):

```nix
fields = {
  enable = sp.bool {
    index = 1;
    description = "Enable deployment for this app";
    default = false;
  };

  backend = sp.enum {
    index = 2;
    values = [ "colmena" "nixos-rebuild" "nixos-anywhere" "alchemy" "fly" "custom" ];
    description = "Deployment backend";
    optional = true;
  };

  targets = sp.string {
    index = 3;
    repeated = true;
    description = "Deployment target names (colmena host names, fly app names, etc.)";
  };

  defaultEnv = sp.string {
    index = 4;
    description = "Default target environment";
    default = "prod";
  };

  command = sp.string {
    index = 5;
    description = "Override deploy command (escape hatch for custom backends)";
    optional = true;
  };
};
```

Backend-specific options live in sub-schemas: `deploy.colmena.*`, `deploy.fly.*`, `deploy.alchemy.*`.

### 7.2 Example config

```nix
# .stackpanel/config.nix
apps = {
  stackpanel-go = {
    # ... existing config ...
    deployment = {
      enable = true;
      backend = "colmena";
      targets = [ "prod-server" ];
      defaultEnv = "prod";
    };
  };

  web = {
    # ... existing config ...
    deployment = {
      enable = true;
      backend = "alchemy";   # CF Workers - genuine exception
      defaultEnv = "prod";
      # existing bindings/secrets fields migrate here
      bindings = [ "DATABASE_URL" "BETTER_AUTH_SECRET" ];
      secrets  = [ "DATABASE_URL" "BETTER_AUTH_SECRET" "POLAR_ACCESS_TOKEN" ];
    };
  };

  docs = {
    # ... existing config ...
    deployment = {
      enable = true;
      backend = "colmena";   # static site served by Nginx on the NixOS host
      targets = [ "prod-server" ];
    };
  };
};
```

---

## 8. CLI Command Design

```
stackpanel deploy [app] [flags]

Commands:
  stackpanel deploy <app>              Deploy an app to its configured target
  stackpanel deploy provision <host>   Provision a new NixOS host (nixos-anywhere)
  stackpanel deploy status [app]       Show last deploy + live status from backend

Flags:
  --env string       Target environment  (default: app's deployment.defaultEnv)
  --target string    Override configured target host / fly app / etc.
  --dry-run          Show what would change without executing
  --no-build         Skip nix build; use cached derivation
  --backend string   Override backend from config
  --verbose          Show full backend stdout/stderr
```

In Go (`apps/stackpanel-go/cmd/cli/deploy.go`):

```go
func deployApp(appName, env string, flags DeployFlags) error {
    // 1. Load deployment config via nix eval
    cfg := nixconfig.LoadDeployConfig(appName)
    if !cfg.Enable {
        return fmt.Errorf("app %q has no deployment config", appName)
    }

    // 2. Resolve environment
    targetEnv := coalesce(flags.Env, cfg.DefaultEnv, "prod")

    // 3. Resolve secrets - write to temp file, defer cleanup
    secretsFile, cleanup, err := secrets.ResolveTempFile(appName, targetEnv)
    defer cleanup()

    // 4. Delegate to backend
    backend := resolveBackend(cfg.Backend)
    result, err := backend.Deploy(DeployContext{
        App:         cfg,
        Env:         targetEnv,
        SecretsFile: secretsFile,
        DryRun:      flags.DryRun,
    })

    // 5. Record in state
    state.RecordDeploy(appName, targetEnv, result)
    return err
}
```

### 8.1 Secrets handling

Secrets are never passed via command-line arguments (shell history) or plain env vars into child processes. Instead:

1. CLI decrypts secrets for the target environment via SOPS
2. Writes to a temp file (`/tmp/stackpanel-deploy-<pid>-<rand>.env`, chmod 600)
3. Passes the file path to the backend (e.g., `fly secrets import < <file>`, `EnvironmentFile=` in systemd, Alchemy reads via `dotenv`)
4. Temp file deleted on exit (deferred)

For NixOS backends, secrets don't flow through the CLI at all — sops-nix reads them at activation on the target host, using the host's own keys.

### 8.2 Deploy state

`.stackpanel/state/deployments.json` tracks last-deploy metadata per app per environment:

```json
{
  "stackpanel-go": {
    "prod": {
      "timestamp": "2026-03-10T14:23:00Z",
      "backend": "colmena",
      "target": "prod-server",
      "nixRevision": "abc123",
      "derivation": "/nix/store/...-stackpanel-go-0.1.0"
    }
  }
}
```

`stackpanel deploy status` reads this file plus optionally queries the backend (colmena status, fly status) for live state.

---

## 9. What the Nix Module System Needs to Generate

For the NixOS backend to work, the flake needs to expose `nixosModules` per app. The `app-build` module (or a new `deploy` module) generates these:

```nix
# nix/flake/default.nix - added to flake outputs
nixosModules = lib.mapAttrs (name: app:
  import ./nixos-service.nix { inherit name app pkgs lib; }
) (lib.filterAttrs (_: app: app.deployment.enable or false) cfg.apps);
```

```nix
# nix/stackpanel/modules/deploy/nixos-service.nix
{ name, app, pkgs, lib }:
{ config, inputs, ... }:
{
  systemd.services.${name} = {
    description = app.description or name;
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${inputs.self.packages.${pkgs.system}.${name}}/bin/${app.go.binaryName or name}";
      Restart = "on-failure";
      User = name;
      EnvironmentFile = lib.mkIf (app.deployment.secrets != [])
        config.sops.secrets."${name}-env".path;
    };
  };

  sops.secrets."${name}-env" = lib.mkIf (app.deployment.secrets != []) {
    sopsFile = ./secrets/${app.deployment.defaultEnv or "prod"}.yaml;
    format = "dotenv";
    owner = name;
  };

  users.users.${name} = { isSystemUser = true; group = name; };
  users.groups.${name} = {};
}
```

This makes `inputs.self.nixosModules.stackpanel-go` available for import in colmena host configs. Users who want to customize beyond what the auto-generated module provides can import it and `lib.mkForce` specific options, or write their own service module that uses `inputs.self.packages.x86_64-linux.stackpanel-go` directly.

---

## 10. Trade-offs Summary

| Dimension | NixOS-native (colmena) | Container (Fly) | Alchemy (CF Workers) |
|---|---|---|---|
| Applicable targets | Any Linux VM or bare metal | Any container platform | Cloudflare only |
| Uses Nix derivation directly | ✓ | Via nix2container | ✗ |
| Rollback | NixOS generations (free) | Re-deploy previous image | Alchemy state + redeploy |
| Secrets model | sops-nix on host (coherent) | `fly secrets set` | `alchemy.secret()` |
| macOS developer builds | Remote Linux builder needed | Remote builder needed | ✓ Native |
| Infrastructure provisioning | nixos-anywhere (one-time) | `fly apps create` | Alchemy handles it |
| State management | Nix generations + state file | Fly versioning + state file | Alchemy state file |
| Multi-host management | Colmena (first-class) | Multiple fly apps | Per-stage Alchemy runs |
| Coherence with project | ✓ (Nix all the way) | Partial | Partial |

---

## 11. Open Questions

1. **Where does `colmena.nix` live?** Option A: `.stackpanel/deploy/colmena.nix` (auto-generated, gitignored). Option B: `nix/deploy/colmena.nix` (user-authored, committed). Option B is safer — it's explicit infrastructure config that should be in version control. But stackpanel should generate an initial scaffold.

2. **Should `nixosModules` be auto-generated or user-authored?** Auto-generation from `apps.<name>` config enables `nix build` → deploy without any manual NixOS module writing, which is a compelling UX. But it reduces flexibility. A good middle ground: generate a module, expose it, allow users to override via `apps.<name>.deployment.nixosModule = ./my-custom-module.nix`.

3. **Remote builder preflight:** Before any Linux build on macOS, should the CLI verify the Tailscale builder is reachable? Yes. The config already has the builder's IP and SSH key path — a preflight check is trivial to implement and prevents confusing mid-build failures.

4. **`stackpanel infra` vs `stackpanel deploy`:** Infrastructure provisioning (creating the Neon DB, the CF Worker, the Hetzner VM) is a separate concern from deploying the app to existing infrastructure. Should `stackpanel infra apply` be a separate command? Probably yes, but it can be a later concern — for now, `stackpanel deploy provision` for nixos-anywhere and Alchemy's own provisioning are sufficient.

5. **CI/CD:** The Go agent isn't running in CI, but `stackpanel deploy` should work headlessly. The CLI must be fully functional without the agent. Since the CLI already works standalone (it's how the agent starts), this should be fine, but the deploy command should be designed with CI in mind from the start (non-interactive, machine-readable output with `--json`, exit codes).

6. **Preview environments:** The Alchemy config already supports per-`STAGE` resources. Should `stackpanel deploy --env preview/pr-42` be a first-class concept? For colmena, a preview would need a separate host or a NixOS container (nixos-container). This is non-trivial but worth noting as a future direction.

---

## 12. Proposed Implementation Order

1. **Config schema:** Add `deployment.*` as a proper SpField set in `nix/stackpanel/modules/deploy/schema.nix`, migrating the existing ad-hoc `apps.web.deployment.*` fields
2. **NixOS module generation:** Add `nixosModules` output to the flake, auto-generated from `apps.<name>.deployment` config
3. **`colmena.nix` scaffold:** `stackpanel deploy init` generates `.stackpanel/deploy/colmena.nix` from the apps that have `deployment.backend = "colmena"`
4. **`stackpanel deploy` CLI command:** Thin orchestrator, colmena backend first
5. **`stackpanel deploy provision`:** nixos-anywhere wrapper for initial host setup
6. **Alchemy backend:** Wrap existing `alchemy.run.ts` invocation, inject secrets
7. **Deploy state file:** `.stackpanel/state/deployments.json` with `stackpanel deploy status`
8. **Container/Fly backend:** nix2container integration, builder preflight check
9. **Studio UI panel:** Deployment status per app, trigger deploy from UI (post-CLI)
