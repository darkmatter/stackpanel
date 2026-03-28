# Design: Pluggable Deploy Backends

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Nix Module System                       │
│                                                             │
│  modules/deploy/module.nix         modules/fly/module.nix   │
│  ┌───────────────────────┐         ┌─────────────────────┐  │
│  │ Core deploy framework │         │ Fly backend module   │  │
│  │                       │         │                      │  │
│  │ deployment.backends   │◄────────│ registers backend    │  │
│  │   (registry)          │         │ injects app.fly.*    │  │
│  │                       │         │ provides scripts     │  │
│  │ deployment.specs      │         └─────────────────────┘  │
│  │   (computed per-app)  │                                   │
│  └───────────┬───────────┘         (same for colmena,       │
│              │                      nixos-rebuild, alchemy)  │
│              │ nix eval                                      │
└──────────────┼──────────────────────────────────────────────┘
               │
               ▼
┌──────────────────────────────────────────────────────────────┐
│                      Go CLI (executor)                       │
│                                                              │
│  1. nix eval → resolved scripts (bash strings) + app config  │
│  2. Assemble context.json with runtime values                │
│  3. Write script + context to temp files                     │
│  4. exec: bash /tmp/sp-deploy-XXXX.sh /tmp/sp-ctx-XXXX.json │
│  5. Capture exit code, record to .stack/state/deployments.json│
└──────────────────────────────────────────────────────────────┘
```

## Backend Module Structure

```
nix/stackpanel/modules/<backend>/
  ├── meta.nix       # features.deployBackend = true
  └── module.nix     # registers backend + per-app options
```

### Registration

Each backend module writes to `config.stackpanel.deployment.backends.<id>`:

```nix
config.stackpanel.deployment.backends.fly = {
  name = "Fly.io";
  scripts = {
    deploy = { pkgs, lib, app, backendConfig, machines, projectRoot, stateDir }:
      ''
        CTX="$1"
        APP_NAME=$(jq -r '.backendConfig.appName' "$CTX")
        # ...
        fly deploy --config fly.toml
      '';
    dryRun = { ... }: '' ... '';
    status = { ... }: '' ... '';   # optional
    validate = { ... }: '' ... ''; # optional
  };
};
```

### Per-app options (via appModules)

```nix
config.stackpanel.appModules = [
  ({ lib, ... }: {
    options.fly = {
      appName = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; };
      region = lib.mkOption { type = lib.types.str; default = "iad"; };
      vm = lib.mkOption {
        type = lib.types.submodule { ... };
        default = { memory = "1gb"; cpuKind = "shared"; cpus = 1; };
      };
    };
  })
];
```

## Core Deploy Module

### Backend registry option

```nix
# In modules/deploy/module.nix
options.stackpanel.deployment.backends = lib.mkOption {
  type = lib.types.attrsOf (lib.types.submodule {
    options = {
      name = lib.mkOption { type = lib.types.str; };
      scripts = {
        deploy = lib.mkOption {
          type = lib.types.functionTo lib.types.str;
          description = "Function receiving Nix args, returns bash script string";
        };
        dryRun = lib.mkOption {
          type = lib.types.functionTo lib.types.str;
          description = "Function receiving Nix args, returns bash script for dry-run";
        };
        status = lib.mkOption {
          type = lib.types.functionTo lib.types.str;
          default = _: "echo 'status not implemented for this backend'";
        };
        validate = lib.mkOption {
          type = lib.types.functionTo lib.types.str;
          default = _: "true";
        };
      };
    };
  });
  default = {};
};
```

### Spec computation (resolves scripts at eval time)

```nix
config.stackpanel.deployment.specs = lib.mapAttrs (appName: app:
  let
    backend = cfg.deployment.backends.${app.deployment.backend};
    nixArgs = {
      inherit pkgs lib;
      inherit (cfg) projectRoot stateDir;
      app = app // { name = appName; };
      backendConfig = app.${app.deployment.backend} or {};
      machines = cfg.deployment.machines;
    };
  in {
    inherit appName;
    backend = app.deployment.backend;
    env = app.deployment.defaultEnv;
    scripts = lib.mapAttrs (_: fn: fn nixArgs) backend.scripts;
  }
) deployableApps;
```

The computed specs are serialized to JSON. The `scripts` field contains fully resolved bash strings.

## Context JSON Schema

Written by the Go CLI at deploy time. Passed as `$1` to the script.

```json
{
  "app": {
    "name": "docs",
    "path": "apps/docs",
    "port": 6400
  },
  "backend": "fly",
  "backendConfig": {
    "appName": "stackpanel-docs",
    "region": "iad",
    "vm": { "memory": "1gb", "cpuKind": "shared", "cpus": 1 }
  },
  "env": "prod",
  "dryRun": false,
  "gitRevision": "a1b2c3d",
  "timestamp": "2026-03-28T12:00:00Z",
  "projectRoot": "/home/user/stackpanel",
  "stateDir": "/home/user/stackpanel/.stack/state",
  "machines": {
    "ovh-usw-1": {
      "host": "15.204.104.4",
      "user": "root",
      "sshPort": 22,
      "proxyJump": null
    }
  },
  "targets": ["ovh-usw-1"]
}
```

## Backend Examples

### Colmena (ported from deploy.go, logic unchanged)

```nix
scripts.deploy = { app, machines, ... }: ''
  CTX="$1"
  DRY_RUN=$(jq -r '.dryRun' "$CTX")
  TARGETS=$(jq -r '.targets | join(",")' "$CTX")

  if [ "$DRY_RUN" = "true" ]; then
    colmena --impure build --on "$TARGETS"
  else
    colmena --impure apply --on "$TARGETS"
  fi
'';
```

### Fly (new)

```nix
scripts.deploy = { pkgs, lib, app, backendConfig, ... }: let
  flyToml = pkgs.lib.generators.toTOML {} {
    app = backendConfig.appName;
    http_service = {
      internal_port = app.port;
      force_https = true;
      auto_stop_machines = "suspend";
      auto_start_machines = true;
    };
    vm = [{ memory = backendConfig.vm.memory; cpu_kind = backendConfig.vm.cpuKind; cpus = backendConfig.vm.cpus; }];
  };
in ''
  CTX="$1"
  DRY_RUN=$(jq -r '.dryRun' "$CTX")
  APP_DIR=$(jq -r '.app.path' "$CTX")

  cd "$APP_DIR"
  cat > fly.toml <<'FLYEOF'
  ${flyToml}
  FLYEOF

  if [ "$DRY_RUN" = "true" ]; then
    echo "Would deploy to Fly app: ${backendConfig.appName}"
    cat fly.toml
  else
    fly deploy --config fly.toml
  fi
'';
```

### Alchemy (ported from deploy.go, logic unchanged)

```nix
scripts.deploy = { app, ... }: ''
  CTX="$1"
  DRY_RUN=$(jq -r '.dryRun' "$CTX")
  ENV=$(jq -r '.env' "$CTX")
  PROJECT_ROOT=$(jq -r '.projectRoot' "$CTX")

  # Find alchemy entrypoint
  for candidate in \
    "$PROJECT_ROOT/alchemy.run.ts" \
    "$PROJECT_ROOT/infra/alchemy.ts" \
    "$PROJECT_ROOT/apps/${app.name}/alchemy.run.ts" \
    "$PROJECT_ROOT/apps/${app.name}/infra/alchemy.ts"; do
    if [ -f "$candidate" ]; then
      ENTRYPOINT="$candidate"
      break
    fi
  done
  ENTRYPOINT=''${ENTRYPOINT:-"$PROJECT_ROOT/alchemy.run.ts"}

  if [ "$DRY_RUN" = "true" ]; then
    echo "dry-run: STAGE=$ENV bun run $ENTRYPOINT"
  else
    STAGE="$ENV" bun run "$ENTRYPOINT"
  fi
'';
```

## Decisions

1. **Scripts, not command arrays.** Backends return bash scripts that can do anything. No assumptions about deploy being a single command.

2. **Two-layer input.** Nix args for config-time values (pkgs, lib, app config, machine definitions). Context JSON for runtime values (dry-run flag, git rev, secrets, env overrides).

3. **Go CLI is a generic executor.** No backend-specific Go code. Reads resolved scripts from nix eval, writes context.json, executes, records state.

4. **NixOS path is frozen.** Colmena and nixos-rebuild scripts produce identical commands to today's Go functions. The business logic does not change.

5. **Backend options via appModules.** Each backend injects its own per-app options (fly.appName, alchemy.workerName, etc.) following the established module pattern.

6. **Proto simplification.** The proto `DeploymentProvider` enum should be reconciled or replaced with a generic shape that matches the script-based model. TBD in implementation.
