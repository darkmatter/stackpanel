# Pluggable Deploy Backends

## Problem

The deployment system works (colmena, nixos-rebuild, and alchemy all deploy successfully) but it's hardcoded in three places that don't agree:

- **Nix** (`deploy/module.nix`): enum of `colmena | nixos-rebuild | alchemy | fly | custom`
- **Go CLI** (`deploy.go`): switch/case with backend-specific Go functions
- **Proto** (`deployment.proto`): different enum entirely (`cloudflare | fly | aws_ecs | railway | render`)

Adding a new backend (e.g., Fly) means editing all three plus writing implementation with no clear contract. The module system is well-designed for extension (appModules, serviceModules, auto-discovery) but deployment backends don't use it.

## Approach

**Make deployment backends stackpanel modules.** Each backend is a module under `nix/stackpanel/modules/` that registers itself with the core deploy framework. The Go CLI becomes a generic executor, not a backend-aware dispatcher.

### Backend contract

A backend module provides **scripts** — Nix-evaluated bash strings. At Nix eval time, the module author has full access to `pkgs`, `lib`, `pkgs.lib.generators.toTOML`, etc. At runtime, the script receives a JSON context file with deploy-time values.

```
Nix eval time (module args)          Runtime (context.json)
─────────────────────────            ─────────────────────
pkgs, lib                           dryRun (bool)
app config (ports, domain, type)    gitRevision
backendConfig (fly.appName, etc.)   timestamp
machines (host, user, ssh)          secretRefs
projectRoot, stateDir               env overrides (--env flag)
```

Each backend registers:
- `scripts.deploy` — deploy an app
- `scripts.dryRun` — preview what deploy would do
- `scripts.status` — check deploy status (optional)
- `scripts.validate` — preflight validation (optional)

Each script function receives Nix args and returns a bash string. The resolved script is serialized to the Go CLI, which writes it to a temp file alongside a context.json and executes it.

### Go CLI becomes a generic executor

```
1. nix eval → get resolved scripts + config per app
2. Assemble context.json (runtime values)
3. Write script to temp file
4. Execute: bash /tmp/script.sh /tmp/ctx.json
5. Record exit code + state
```

No switch/case. No backend-specific Go code. A new backend is purely Nix.

### Existing backends are preserved

The NixOS deploy path (colmena/nixos-rebuild) **does not change in business logic**. The exact same commands run — they're just packaged as scripts inside modules instead of Go functions. Same for alchemy.

## Non-goals

- Changing how NixOS deployment works (colmena, nixos-rebuild logic is frozen)
- `provision --new` / config authoring from CLI
- Studio UI (separate follow-up, depends on stable model)
- Abstracting away backend differences (backends are intentionally opaque scripts)

## Phases

### P1: Design & scaffold the backend contract
Define the `deployment.backends` option type in the core deploy module, the context.json schema, and the Go CLI generic executor that replaces the switch/case.

### P2: Port existing backends (behavior-preserving)
Move colmena, nixos-rebuild, and alchemy from Go functions to Nix script modules. Identical commands, different packaging. Delete the Go switch/case once all three produce identical behavior.

### P3: Fly module (first plugin backend)
Implement `nix/stackpanel/modules/fly/` as the first backend built against the contract. fly.toml generation via Nix (e.g., `pkgs.lib.generators.toTOML`), `fly deploy` invocation. This proves the contract works for a new backend without touching core.

### P4: Test matrix — stackpanel
Deploy {docs, web} x {colmena, nixos-rebuild, fly} on stackpanel's own infra. Real deploys, not dry-runs. Machines: ovh-usw-1 (direct), volt-* (behind proxyJump).

### P5: Dogfood — nixmac
Add stackpanel deploy config to ~/git/darkmatter/nixmac. Validate the fly backend against the existing hand-written fly.toml. Prove the system generalizes beyond stackpanel.

### P6: Studio UI + Docs
Wire deploy/provision state into the Studio Deploy panel. Unify deployment docs around the shipped model. Depends on the backend contract being stable.

## Risks

- **Script debugging** — when a deploy script fails, the error context needs to be good enough to diagnose. The Go CLI should capture stderr and relate it back to the backend + app.
- **Secret handling** — scripts may need secrets (FLY_API_TOKEN, etc.). The context.json approach needs a clear pattern for secret references vs. literal values. Scripts should never receive secrets as arguments.
- **Nix eval performance** — generating scripts via nix eval adds to eval time. The existing `deployConfigExpr` is already optimized to avoid full flake eval; the script generation path needs similar care.
- **Proto alignment** — the proto `DeploymentProvider` enum is out of sync with the Nix backend enum. With script-based backends, the proto may simplify to a generic `DeploySpec` message. Needs reconciliation.
