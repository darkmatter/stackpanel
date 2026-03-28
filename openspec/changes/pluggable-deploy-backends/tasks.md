# Tasks: Pluggable Deploy Backends

## P1: Backend contract & scaffold

- [ ] **P1.1** Define `deployment.backends` option type in `modules/deploy/module.nix` (registry with scripts.deploy, scripts.dryRun, scripts.status, scripts.validate)
- [ ] **P1.2** Define the Nix args shape passed to script functions (pkgs, lib, app, backendConfig, machines, projectRoot, stateDir)
- [ ] **P1.3** Add `deployment.specs` computed option that resolves scripts per deployable app at eval time
- [ ] **P1.4** Define context.json schema (runtime values: dryRun, gitRevision, timestamp, env, targets, secretRefs)
- [ ] **P1.5** Refactor Go CLI `deploy.go` to generic executor: read specs from nix eval, write context.json + script to temp files, exec bash, capture exit code, record state
- [ ] **P1.6** Update the nix eval expression (`deployConfigExpr`) to return resolved specs with script strings alongside existing config

## P2: Port existing backends (behavior-preserving)

- [ ] **P2.1** Port colmena to script module — extract `deployColmena()` logic from deploy.go into `modules/deploy/backends/colmena.nix`, register as `deployment.backends.colmena`
- [ ] **P2.2** Port nixos-rebuild to script module — extract `deployNixosRebuild()` logic into `modules/deploy/backends/nixos-rebuild.nix`, register as `deployment.backends.nixos-rebuild`
- [ ] **P2.3** Port alchemy to script module — extract `deployAlchemy()` logic into `modules/deploy/backends/alchemy.nix`, register as `deployment.backends.alchemy`
- [ ] **P2.4** Verify all three produce identical deploy behavior to current Go implementation (same commands, same args, same env vars)
- [ ] **P2.5** Remove backend switch/case and backend-specific functions from deploy.go

## P3: Fly module (first plugin)

- [ ] **P3.1** Create `nix/stackpanel/modules/fly/meta.nix` with `features.deployBackend = true`
- [ ] **P3.2** Create `nix/stackpanel/modules/fly/module.nix` — register `deployment.backends.fly`, inject `app.fly.*` options via appModules (appName, region, vm config)
- [ ] **P3.3** Implement fly.toml generation using `pkgs.lib.generators.toTOML` in the deploy script
- [ ] **P3.4** Implement `scripts.deploy` (generate fly.toml, call `fly deploy`)
- [ ] **P3.5** Implement `scripts.dryRun` (generate fly.toml, call `fly deploy --build-only` or just print)
- [ ] **P3.6** Add fly deployment config to stackpanel apps (docs and/or web) for testing

## P4: Test matrix — stackpanel

- [ ] **P4.1** Ensure docs and web both have Nix packages that build to deployable artifacts (needed for NixOS backends)
- [ ] **P4.2** Deploy docs via colmena to ovh-usw-1 — green
- [ ] **P4.3** Deploy docs via nixos-rebuild to ovh-usw-1 — green
- [ ] **P4.4** Deploy docs via fly — green
- [ ] **P4.5** Deploy web via colmena to ovh-usw-1 — green
- [ ] **P4.6** Deploy web via nixos-rebuild to ovh-usw-1 — green
- [ ] **P4.7** Deploy web via fly — green
- [ ] **P4.8** Add `nix flake check` validation for deployment outputs

## P5: Dogfood — nixmac

- [ ] **P5.1** Add stackpanel deploy config to nixmac project
- [ ] **P5.2** Deploy nixmac web via fly — validate generated fly.toml matches existing hand-written one
- [ ] **P5.3** Verify the module system works in a project that isn't stackpanel itself

## P6: Studio UI + Docs

- [ ] **P6.1** Expose deploy specs + state through agent API (read-only)
- [ ] **P6.2** Update Studio Deploy panel to consume backend-agnostic deploy specs and state
- [ ] **P6.3** Add deploy/provision action triggers from the panel
- [ ] **P6.4** Unify deployment docs around the pluggable backend model
- [ ] **P6.5** Document how to create a new backend module (contributor guide)
