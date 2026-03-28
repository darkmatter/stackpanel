# Design: `stackpanel deploy` Command

> **Superseded by:** `docs/superpowers/specs/2026-03-28-deployment-system.md`
>
> This document is kept as historical design rationale. If it conflicts with the canonical deployment-system spec, follow the canonical spec.

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

The core principle: **the flake outputs are the canonical deployment artifacts.** No files are generated. Deployment-related Nix expressions are computed by the module system and surfaced as standard flake outputs (`nixosConfigurations`, `colmenaHive`, `nixosModules`). Every NixOS-capable tool can consume these directly. `stackpanel deploy` is an optional UX layer on top — it adds preflight checks, secret verification, state tracking, and TUI integration, but is never load-bearing for the actual deployment.

```
config.nix  (single source of truth)
    │
    ▼  Nix module evaluation
    ├── packages.<system>.stackpanel-go     app derivations  (existing)
    ├── nixosModules.stackpanel-go          per-app NixOS service module
    ├── nixosConfigurations.prod-server     full NixOS system per machine
    └── colmenaHive                         colmena hive attrset
                │
                ▼  consumed directly by standard tools:
    colmena apply                                      # multi-host redeploy
    nixos-rebuild switch --flake .#prod-server         # single-host redeploy
    nixos-anywhere --flake .#prod-server root@<ip>     # initial provisioning
                │
                ▼  or via stackpanel (adds UX, preflight, state tracking):
    stackpanel deploy --target prod-server
    stackpanel deploy provision --target root@<ip>
    stackpanel deploy status
```

For PaaS backends:

```
config.nix
    │
    ├── apps.web.deployment.backend = "alchemy"
    │       └── stackpanel deploy web  →  bun run alchemy.run.ts --stage prod
    │
    └── apps.web.deployment.backend = "fly"
            └── stackpanel deploy web  →  nix build .#web-container → fly deploy
```

---

## 4. Detailed Design: Nix-Native Backend (Primary)

### 4.1 How apps become NixOS modules

The deploy module in `nix/stackpanel/modules/deploy/` generates a `nixosModule` for each app that has `deployment.enable = true`. This is a Nix expression computed during module evaluation — not a file written to disk.

```nix
# nix/stackpanel/modules/deploy/nixos-service.nix
#
# Takes a single app's config and returns a NixOS module function.
# The module references inputs.self.packages so the closure is always
# built from the same flake revision being deployed.
{ name, app, lib }:
{ config, inputs, pkgs, ... }:
let
  pkg = inputs.self.packages.${pkgs.system}.${name};
  bin = app.go.binaryName or name;
  hasSecrets = (app.deployment.secrets or {}) != {};
in
{
  systemd.services.${name} = {
    description = app.description or name;
    wantedBy    = [ "multi-user.target" ];
    after       = [ "network.target" ] ++ lib.optional hasSecrets "sops-nix.service";
    serviceConfig = {
      ExecStart       = "${pkg}/bin/${bin}";
      Restart         = "on-failure";
      User            = name;
      EnvironmentFile = lib.mkIf hasSecrets config.sops.secrets."${name}-env".path;
      ProtectSystem   = "strict";
      NoNewPrivileges = true;
    };
  };

  sops.secrets."${name}-env" = lib.mkIf hasSecrets {
    sopsFile = ../secrets/${app.deployment.defaultEnv or "prod"}.yaml;
    format   = "dotenv";
    owner    = name;
  };

  users.users.${name} = { isSystemUser = true; group = name; };
  users.groups.${name} = {};
}
```

Users who need to customise beyond what the generated module provides can import it and override specific options with `lib.mkForce`, or bypass it entirely by setting `apps.<name>.deployment.nixosModule = ./my-custom-module.nix`.

### 4.2 Machine definitions in config.nix

The deployment topology — which machines exist and how to reach them — lives in `config.nix` as a new top-level `deployment.machines` section. This is user-authored, committed to the repo, never generated.

```nix
# .stackpanel/config.nix
deployment = {
  machines = {
    prod-server = {
      host   = "prod.example.com";  # SSH target for colmena / nixos-rebuild
      user   = "root";
      system = "x86_64-linux";
      # Hardware config path — generated once by nixos-anywhere, then committed
      hardwareConfig = ./hosts/prod-server/hardware-configuration.nix;
      # Optional extra NixOS modules (firewall rules, extra packages, etc.)
      extraModules = [];
    };
    staging-server = {
      host   = "staging.example.com";
      user   = "root";
      system = "x86_64-linux";
      hardwareConfig = ./hosts/staging-server/hardware-configuration.nix;
    };
  };
};
```

Apps then reference machine names in their `deployment.targets`:

```nix
apps.stackpanel-go.deployment = {
  enable  = true;
  backend = "colmena";
  targets = [ "prod-server" ];
};

apps.docs.deployment = {
  enable  = true;
  backend = "colmena";
  targets = [ "prod-server" "staging-server" ];
};
```

### 4.3 `mkHive` and `mkNixosConfigurations`

Two library functions in `nix/stackpanel/lib/deploy.nix` drive the flake output generation. They read from the evaluated stackpanel config — no new files, no codegen, just pure Nix.

```nix
# nix/stackpanel/lib/deploy.nix
{ lib }:
{
  # ---------------------------------------------------------------------------
  # mkHive
  #
  # Produces a colmena hive attrset. colmena discovers this via the flake's
  # top-level `colmenaHive` attribute.
  #
  # Each machine node imports the nixosModules for all apps that list it in
  # deployment.targets, plus the machine's own hardware config and extraModules.
  # ---------------------------------------------------------------------------
  mkHive = { config, inputs, nixpkgs }:
    let
      machines  = config.deployment.machines or {};
      deployedApps = lib.filterAttrs
        (_: app: app.deployment.enable or false
               && (app.deployment.backend or "") == "colmena")
        config.apps;

      # appName -> list of machine names it deploys to
      appTargets = lib.mapAttrs
        (_: app: app.deployment.targets or [])
        deployedApps;

      # machine name -> list of app names deployed to it
      appsForMachine = machineName:
        lib.attrNames (lib.filterAttrs
          (_: targets: lib.elem machineName targets)
          appTargets);
    in
    {
      meta = {
        nixpkgs     = import nixpkgs { system = "x86_64-linux"; };
        specialArgs = { inherit inputs; };
      };
    }
    // lib.mapAttrs (machineName: machine:
      { pkgs, inputs, ... }:
      {
        deployment = {
          targetHost = machine.host;
          targetUser = machine.user or "root";
        };
        imports =
          [ machine.hardwareConfig ]
          ++ (machine.extraModules or [])
          ++ map (appName: inputs.self.nixosModules.${appName})
                 (appsForMachine machineName);
      }
    ) machines;

  # ---------------------------------------------------------------------------
  # mkNixosConfigurations
  #
  # Produces nixosConfigurations — one per machine. These are consumed by:
  #   nixos-rebuild switch --flake .#<machine>
  #   nixos-anywhere   --flake .#<machine> root@<ip>
  # ---------------------------------------------------------------------------
  mkNixosConfigurations = { config, inputs, nixpkgs }:
    let
      machines = config.deployment.machines or {};
      deployedApps = lib.filterAttrs
        (_: app: app.deployment.enable or false)
        config.apps;

      appsForMachine = machineName:
        lib.attrNames (lib.filterAttrs
          (_: app: lib.elem machineName (app.deployment.targets or []))
          deployedApps);
    in
    lib.mapAttrs (machineName: machine:
      nixpkgs.lib.nixosSystem {
        system      = machine.system or "x86_64-linux";
        specialArgs = { inherit inputs; };
        modules     =
          [ machine.hardwareConfig ]
          ++ (machine.extraModules or [])
          ++ map (appName: inputs.self.nixosModules.${appName})
                 (appsForMachine machineName);
      }
    ) machines;
}
```

### 4.4 Flake adapter hooks

In `nix/flake/default.nix`, alongside the existing `packages`, `checks`, `apps` outputs:

```nix
let
  deployLib = import ../stackpanel/lib/deploy.nix { inherit lib; };
  deployArgs = { inherit config inputs; nixpkgs = inputs.nixpkgs; };
in
{
  # Existing outputs
  packages = sp.outputs;
  apps     = sp.flakeApps;
  checks   = sp.checks;

  # New: per-app NixOS service modules (importable by any NixOS config)
  nixosModules = sp.nixosModules;

  # New: per-machine full NixOS configurations
  # Used by: nixos-rebuild, nixos-anywhere
  nixosConfigurations = deployLib.mkNixosConfigurations deployArgs;

  # New: colmena hive (colmena looks for this top-level attribute in the flake)
  # Used by: colmena apply
  colmenaHive = deployLib.mkHive deployArgs;
}
```

After this, no stackpanel involvement is needed to run a deployment:

```bash
# Provision a new machine (one-time)
nixos-anywhere --flake .#prod-server root@1.2.3.4

# Deploy updated apps to existing machine (any of these work):
colmena apply --on prod-server
nixos-rebuild switch --flake .#prod-server --target-host root@prod.example.com

# Or via stackpanel (adds preflight, state, TUI):
stackpanel deploy --target prod-server
```

### 4.5 Initial provisioning with nixos-anywhere

For a brand-new machine, nixos-anywhere reads `nixosConfigurations.prod-server` from the flake and installs NixOS from scratch on any bare Linux host:

```
stackpanel deploy provision prod-server --ip 1.2.3.4
  1. Preflight: verify SSH connectivity to root@1.2.3.4
  2. nixos-anywhere --flake .#prod-server root@1.2.3.4
     (partitions, installs NixOS, copies secrets if disko config present)
  3. Record in .stackpanel/state/deployments.json
```

nixos-anywhere generates a `hardware-configuration.nix` on the new host; the user commits this to the repo at the path declared in `machines.prod-server.hardwareConfig`.

### 4.6 Secrets at deployment time

For NixOS targets, secrets do not flow through `stackpanel deploy` at all. sops-nix handles them at activation on the host:

- The NixOS module declares `sops.secrets."<app>-env"` pointing to the relevant SOPS file in `.stackpanel/secrets/`
- The SOPS file is committed to the repo (encrypted)
- At activation, sops-nix decrypts it using the host's SSH host key (or an AGE key provisioned by nixos-anywhere)
- The decrypted dotenv file is written to `/run/secrets/<app>-env` and referenced by `EnvironmentFile=` in the systemd service

This is coherent with the existing secrets architecture. The `.stackpanel/secrets/prod.yaml` SOPS file already exists; the deploy module just adds a sops-nix declaration that reads it.

The deployment config declares which secret keys each app needs:

```nix
apps.stackpanel-go.deployment = {
  enable  = true;
  backend = "colmena";
  targets = [ "prod-server" ];
  secrets = [ "DATABASE_URL" "AUTH_SECRET" ];  # keys expected in prod.yaml
};
```

---

## 5. Detailed Design: Alchemy Backend (Cloudflare Workers Exception)

The Cloudflare Workers case is genuinely different. Workers run in V8 isolates; they are not Linux processes and cannot be wrapped in a systemd service. Alchemy is the right tool.

`stackpanel deploy web --env prod` for a Cloudflare-hosted app maps to:

```
1. Verify SOPS secrets for "prod" are decryptable
2. exec: STAGE=prod bun run alchemy.run.ts
   (Alchemy deploys CF Worker, Neon branch, Upstash Redis)
3. Record deploy metadata in .stackpanel/state/deployments.json
```

The existing `alchemy.run.ts` / `infra/alchemy/index.ts` already handles this. The `stackpanel deploy` CLI is a thin wrapper that:
- Resolves the correct `STAGE` from the `--env` flag
- Injects decrypted secrets as env vars (written to temp file, not shell args)
- Invokes Alchemy with those env vars
- Captures and surfaces the output

The key config distinction: `apps.web.deployment.backend = "alchemy"` vs `apps.stackpanel-go.deployment.backend = "colmena"`.

---

## 6. Detailed Design: Container Backend (Fly, ECS)

For apps targeting container platforms, nix2container is already configured in the project. The deploy pipeline:

```
stackpanel deploy web --backend fly --env prod
  1. Preflight: verify Linux builder reachable (macOS check)
  2. nix build .#web-container  (OCI image via nix2container)
  3. fly secrets set --app myapp-prod \
       $(stackpanel secrets export --app web --env prod --format fly)
  4. fly deploy --app myapp-prod --image <store path>
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
    values = [ "colmena" "nixos-rebuild" "alchemy" "fly" "custom" ];
    description = "Deployment backend";
    optional = true;
  };

  targets = sp.string {
    index = 3;
    repeated = true;
    description = "Machine names (from deployment.machines) this app deploys to";
  };

  defaultEnv = sp.string {
    index = 4;
    description = "Default target environment";
    default = "prod";
  };

  secrets = sp.string {
    index = 5;
    repeated = true;
    description = "Secret keys required by this app at runtime (from SOPS prod.yaml)";
  };

  nixosModule = sp.string {
    index = 6;
    description = "Path to custom NixOS module (overrides auto-generated service module)";
    optional = true;
  };

  command = sp.string {
    index = 7;
    description = "Override deploy command (escape hatch for custom backends)";
    optional = true;
  };
};
```

### 7.2 Top-level machine definitions (non-serializable, Nix-only)

Machine definitions are Nix-only (they reference file paths and system strings) and live in the stackpanel module as a separate option, not serialized to proto:

```nix
# nix/stackpanel/modules/deploy/module.nix
options.stackpanel.deployment.machines = lib.mkOption {
  type = lib.types.attrsOf (lib.types.submodule {
    options = {
      host           = lib.mkOption { type = lib.types.str; };
      user           = lib.mkOption { type = lib.types.str; default = "root"; };
      system         = lib.mkOption { type = lib.types.str; default = "x86_64-linux"; };
      hardwareConfig = lib.mkOption { type = lib.types.path; };
      extraModules   = lib.mkOption { type = lib.types.listOf lib.types.deferredModule; default = []; };
    };
  });
  default = {};
};
```

### 7.3 Example config

```nix
# .stackpanel/config.nix
deployment = {
  machines = {
    prod-server = {
      host           = "prod.example.com";
      system         = "x86_64-linux";
      hardwareConfig = ./hosts/prod-server/hardware-configuration.nix;
    };
  };
};

apps = {
  stackpanel-go = {
    # ... existing config ...
    deployment = {
      enable    = true;
      backend   = "colmena";
      targets   = [ "prod-server" ];
      secrets   = [ "DATABASE_URL" "AUTH_SECRET" ];
    };
  };

  web = {
    # ... existing config ...
    deployment = {
      enable     = true;
      backend    = "alchemy";        # CF Workers — genuine exception
      defaultEnv = "prod";
      bindings   = [ "DATABASE_URL" "BETTER_AUTH_SECRET" ];
      secrets    = [ "DATABASE_URL" "BETTER_AUTH_SECRET" "POLAR_ACCESS_TOKEN" ];
    };
  };

  docs = {
    # ... existing config ...
    deployment = {
      enable  = true;
      backend = "colmena";           # static site served by Nginx on NixOS host
      targets = [ "prod-server" ];
    };
  };
};
```

---

## 8. CLI Command Design

`stackpanel deploy` is an optional convenience wrapper. The flake outputs work standalone with raw tools; the CLI adds preflight checks, secret verification, progress display, and state tracking.

```
stackpanel deploy [app|--target machine] [flags]

Commands:
  stackpanel deploy [app]              Deploy an app via its configured backend
  stackpanel deploy --target <host>    Deploy all apps targeting a machine (runs colmena)
  stackpanel deploy provision <host>   Provision a new NixOS host (nixos-anywhere)
  stackpanel deploy status [app]       Show last deploy + live status

Flags:
  --env string       Target environment  (default: app's deployment.defaultEnv)
  --target string    Override configured target machine
  --dry-run          Show what would change without executing
  --no-build         Skip nix build; use cached derivation
  --verbose          Show full backend stdout/stderr
  --json             Machine-readable output (for CI)
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

    // 3. Preflight checks (backend-specific)
    backend := resolveBackend(cfg.Backend)
    if err := backend.Preflight(cfg); err != nil {
        return fmt.Errorf("preflight failed: %w", err)
    }

    // 4. For NixOS backends: no secrets needed here — sops-nix handles on-host.
    //    For PaaS backends: decrypt to temp file, defer cleanup.
    var secretsFile string
    if backend.NeedsSecrets() {
        var cleanup func()
        var err error
        secretsFile, cleanup, err = secrets.ResolveTempFile(appName, targetEnv)
        if err != nil { return err }
        defer cleanup()
    }

    // 5. Deploy
    result, err := backend.Deploy(DeployContext{
        App: cfg, Env: targetEnv, SecretsFile: secretsFile, DryRun: flags.DryRun,
    })

    // 6. Record in state
    state.RecordDeploy(appName, targetEnv, result)
    return err
}
```

### 8.1 NixOS backend implementation

```go
type ColmenaBackend struct{}

func (b *ColmenaBackend) NeedsSecrets() bool { return false } // sops-nix handles it

func (b *ColmenaBackend) Preflight(cfg DeployConfig) error {
    // Verify colmena is in PATH
    // Verify SSH key is available
    // Verify flake evaluates (nix flake show --json)
    return nil
}

func (b *ColmenaBackend) Deploy(ctx DeployContext) (DeployResult, error) {
    targets := strings.Join(ctx.App.Targets, ",")
    cmd := exec.Command("colmena", "apply", "--on", targets)
    if ctx.DryRun {
        cmd = exec.Command("colmena", "build", "--on", targets)
    }
    // stream output to TUI / --verbose / --json
    return run(cmd)
}
```

### 8.2 Secrets handling (PaaS backends)

For PaaS backends where secrets flow through the CLI:

1. CLI decrypts secrets for the target environment via SOPS
2. Writes to a temp file (`/tmp/stackpanel-deploy-<pid>-<rand>.env`, chmod 600)
3. Passes file path to backend (e.g., `fly secrets import < <file>`, Alchemy reads via `dotenv`)
4. Temp file deleted on exit (deferred)

Secrets are never passed via command-line arguments or shell env (shell history, `/proc/<pid>/environ` exposure).

### 8.3 Deploy state

`.stackpanel/state/deployments.json` tracks last-deploy metadata per app per environment:

```json
{
  "stackpanel-go": {
    "prod": {
      "timestamp":   "2026-03-10T14:23:00Z",
      "backend":     "colmena",
      "target":      "prod-server",
      "nixRevision": "abc123def456",
      "derivation":  "/nix/store/...-stackpanel-go-0.1.0"
    }
  }
}
```

`stackpanel deploy status` reads this file and optionally queries the backend for live state (colmena's unit status via SSH, fly status --json, etc.).

---

## 9. NixOS Module and Hive Generation (Nix Layer)

This section describes the complete Nix-side of the deploy feature. No files are written to disk; everything is computed by the module system and surfaced as flake outputs.

### 9.1 Deploy module structure

```
nix/stackpanel/modules/deploy/
  module.nix      # options + wires nixosModules into stackpanel.nixosModules
  schema.nix      # per-app deployment SpFields (serializable)
  nixos-service.nix  # function: app config → NixOS module
  meta.nix

nix/stackpanel/lib/
  deploy.nix      # mkHive, mkNixosConfigurations
```

### 9.2 Module output: `stackpanel.nixosModules`

The deploy module computes a `nixosModules` attrset:

```nix
# nix/stackpanel/modules/deploy/module.nix (excerpt)
config.stackpanel.nixosModules =
  lib.mapAttrs (name: app:
    let customModule = app.deployment.nixosModule or null; in
    if customModule != null
    then import customModule  # user override
    else import ./nixos-service.nix { inherit name app lib; }
  ) (lib.filterAttrs (_: app: app.deployment.enable or false) cfg.apps);
```

### 9.3 Flake adapter routes to standard outputs

```nix
# nix/flake/default.nix (additions)
let
  deployLib = import ../stackpanel/lib/deploy.nix { inherit lib; };
  deployArgs = { inherit config inputs; nixpkgs = inputs.nixpkgs; };
in
{
  # Standard outputs consumed by NixOS tooling:
  nixosModules        = sp.nixosModules;
  nixosConfigurations = deployLib.mkNixosConfigurations deployArgs;
  colmenaHive         = deployLib.mkHive deployArgs;
}
```

### 9.4 Verification

Because `nixosConfigurations` is a standard flake output, `nix flake check` validates the NixOS configs as part of the normal check suite. This means a broken NixOS service definition is caught in CI before anyone runs `colmena apply`.

A check can be added explicitly:

```nix
checks = lib.mapAttrs' (name: nixosCfg:
  lib.nameValuePair "nixos-${name}" nixosCfg.config.system.build.toplevel
) nixosConfigurations;
```

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
| Works without stackpanel CLI | ✓ (colmena, nixos-rebuild) | Partially | ✓ (bun run alchemy.run.ts) |
| Coherence with project | ✓ (Nix all the way) | Partial | Partial |

---

## 11. Open Questions

1. **`nixosConfigurations` vs separate `colmenaHive`:** colmena can consume `nixosConfigurations` directly (via `--flake .#nixosConfigurations.prod-server`) but its native format is `colmenaHive` which adds per-node `deployment.*` metadata (targetHost, SSH keys, tags). Should stackpanel expose both, or only `nixosConfigurations` and let users who want colmena features add a `colmena.nix` that imports the generated configs? Both is the most flexible answer, but adds surface area.

2. **`hardwareConfig` bootstrapping:** nixos-anywhere generates `hardware-configuration.nix` but writes it to the remote host. The user needs to copy it back to the repo and commit it before the flake config is complete. Should `stackpanel deploy provision` do this automatically (scp back + git add)? Automating this is convenient but makes the provision command stateful and harder to test.

3. **Remote builder preflight:** Before any Linux build on macOS, the CLI should verify the Tailscale builder is reachable. The config already has the builder's IP and SSH key path — a preflight check is trivial to implement and prevents confusing mid-build failures.

4. **`stackpanel infra` vs `stackpanel deploy`:** Infrastructure provisioning (creating the Neon DB, the CF Worker, the Hetzner VM) is a separate concern from deploying the app to existing infrastructure. Should `stackpanel infra apply` be a separate command? Probably yes, but for now `stackpanel deploy provision` for nixos-anywhere and Alchemy's own provisioning are sufficient.

5. **CI/CD:** The Go agent isn't running in CI, but `stackpanel deploy` should work headlessly. `--json` output and explicit exit codes are required from the start. Secrets in CI need careful handling — either the CI environment has the SOPS master key, or secrets are managed out-of-band (e.g., GitHub Actions secrets injected separately from SOPS).

6. **Preview environments:** For colmena, a preview environment would need a separate machine entry or a NixOS container (`nixos-container`). The Alchemy config already supports per-`STAGE` resources. This is worth noting as a future direction but not blocking v1.

---

## 12. Proposed Implementation Order

1. **Deploy schema:** Add `deployment.*` as a proper SpField set in `nix/stackpanel/modules/deploy/schema.nix`, migrating existing ad-hoc `apps.web.deployment.*` fields
2. **Machine options:** Add `stackpanel.deployment.machines` as a Nix-only option in the deploy module
3. **`nixosModules` output:** Compute per-app NixOS service modules in deploy module; route to flake `nixosModules` output
4. **`mkNixosConfigurations` + `mkHive`:** Implement lib functions; wire into flake adapter as `nixosConfigurations` and `colmenaHive`
5. **`nix flake check` integration:** Add `nixos-<machine>` entries to `checks` output
6. **`stackpanel deploy` CLI command:** Thin orchestrator, colmena backend first (calls `colmena apply`)
7. **`stackpanel deploy provision`:** nixos-anywhere wrapper; optionally copies back `hardware-configuration.nix`
8. **Alchemy backend:** Wrap existing `alchemy.run.ts` invocation, inject secrets via temp file
9. **Deploy state file:** `.stackpanel/state/deployments.json` with `stackpanel deploy status`
10. **Container/Fly backend:** nix2container integration, builder preflight check
11. **Studio UI panel:** Deployment status per app, trigger deploy from UI (post-CLI)
