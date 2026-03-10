# Design: `stackpanel deploy` Command

**Status:** Draft
**Date:** 2026-03-10

---

## 1. Context and Scope

Stackpanel already has fragments of deployment thinking scattered across the codebase:

- `apps.web.deployment.host = "cloudflare"` with `bindings` and `secrets` fields
- `deployment.fly.organization = "darkmatter"` at the top level
- `alchemy.run.ts` / `infra/alchemy/index.ts` for actual Cloudflare + Neon + Upstash provisioning
- App derivations from `nix build .#web`, `nix build .#stackpanel-go` (recent PR)
- Secrets managed via SOPS/chamber with environment scoping

The goal is a first-class `stackpanel deploy [app] [--env staging]` command that orchestrates deployment using any of several backends, while making the Nix derivations built by the `app-build` module a first-class input to that process.

---

## 2. Questioning the Premise

Before designing, it is worth challenging several assumptions embedded in the task description.

### 2.1 "Various deployment backends" may be the wrong abstraction

Grouping nixos-rebuild, colmena, nixos-anywhere, alchemy, and terraform under a single abstraction hides a fundamental split:

| Class | Examples | What you're doing |
|---|---|---|
| **Infrastructure provisioning** | terraform, alchemy, nixos-anywhere | Creating/modifying cloud resources (VMs, databases, DNS) |
| **Service activation** | nixos-rebuild, colmena | Applying a new config to an already-provisioned host |
| **App delivery** | fly deploy, CF Wrangler, docker push | Pushing a built artifact to a runtime platform |

These three classes have different trigger conditions, different state models, and different failure modes. A single `stackpanel deploy` that flattens them risks making each use case worse rather than better.

**Alternative framing:** rather than "one deploy command, many backends," consider two orthogonal concerns:
1. `stackpanel infra` — manages cloud resources (terraform/alchemy/pulumi)
2. `stackpanel deploy` — pushes an app artifact to an already-provisioned target

This document focuses on (2) but acknowledges (1) where it touches the design.

### 2.2 Nix derivations are not always the right deployment artifact

For NixOS-based deployment (nixos-rebuild, colmena), the thing being deployed is a **NixOS system configuration**, not an individual app derivation. The app derivation becomes a closure inside the NixOS config. This is a subtly different model from "build the app, copy it somewhere."

For container-based platforms (Fly, ECS, Cloud Run), the artifact is an OCI image. Nix can produce these (via nix2container, which is already configured), but this path requires a Linux builder and cross-compilation when the developer is on macOS.

For serverless platforms (Cloudflare Workers), the artifact is a JS bundle produced by Vite/Wrangler, not a Nix derivation at all. The existing `bun.buildPhase = "bun run build:fly"` hint and the Alchemy Vite integration are already the right model here.

**Consequence:** the `app-build` module's derivations are most directly useful for NixOS-based and bare-VM deployment. For PaaS/serverless, the deployment tool typically drives its own build step.

### 2.3 Should `stackpanel deploy` be in the CLI at all?

An alternative: `stackpanel deploy` is just a thin wrapper that invokes the backend's native CLI with stackpanel-resolved config injected. The real value stackpanel adds is:

- Resolving secrets for the target environment
- Knowing which app → which backend → which credentials
- Providing a uniform status/log surface in the TUI

The actual deployment mechanics remain with the best-in-class tool for each backend. This is the principle already followed for secrets (SOPS/chamber), services (process-compose), and certs (Step CA).

---

## 3. Design Approaches

### Approach A: Thin Orchestrator (Recommended for v1)

`stackpanel deploy` reads per-app deployment config, resolves secrets, and delegates to the appropriate backend CLI.

```
stackpanel deploy web --env prod
  1. Read apps.web.deployment from config
  2. Resolve which backend: cloudflare
  3. Decrypt prod secrets via SOPS/chamber
  4. exec: alchemy run --env prod (or bun run deploy)
```

**Configuration shape:**

```nix
# .stackpanel/config.nix
apps.web.deployment = {
  enable = true;
  backend = "alchemy";        # or "fly" | "colmena" | "nixos-rebuild" | "custom"
  env = "prod";               # default target environment
  command = "bun run deploy"; # override the derived command (escape hatch)
};
```

**Pros:**
- Minimal new code — mostly wiring
- Each backend stays authoritative for its own concerns
- Escape hatch via `command` covers non-standard cases
- Fits the existing "stackpanel wraps tools" architecture

**Cons:**
- Limited ability to provide a unified status/diff view
- Each backend has different auth, different state, different failure modes — the UX is only as smooth as the worst backend
- "What's deployed now?" requires querying each backend separately

---

### Approach B: Nix-Native Deployment (NixOS-centric)

For teams deploying to NixOS machines (VMs, bare metal, Hetzner, AWS EC2), the deployment target is a NixOS module system configuration. The app derivation becomes a NixOS service.

The deployment module would generate NixOS module snippets from app config:

```nix
# Generated NixOS system config for app "stackpanel-go"
{
  systemd.services.stackpanel-go = {
    description = "Stackpanel CLI and agent";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${inputs.self.packages.x86_64-linux.stackpanel-go}/bin/stackpanel agent";
      Restart = "always";
      User = "stackpanel";
      EnvironmentFile = "/run/secrets/stackpanel-go-env";
    };
  };
  sops.secrets."stackpanel-go-env".sopsFile = ./secrets/prod.yaml;
}
```

Managed via **colmena** for multi-host or **nixos-rebuild** for single-host:

```nix
# .stackpanel/deploy/colmena.nix
{
  meta.nixpkgs = import <nixpkgs> {};

  "prod-server" = { pkgs, ... }: {
    imports = [ stackpanel.nixosModules.stackpanel-go ];
    deployment.targetHost = "prod.example.com";
  };
}
```

```
stackpanel deploy stackpanel-go --env prod
  1. nix build .#stackpanel-go (get the derivation)
  2. colmena build --on prod-server (build NixOS system with app inside)
  3. colmena apply --on prod-server
```

**Pros:**
- Full Nix closure guarantees — every dependency deployed as a unit
- `nixos-anywhere` handles initial provisioning of bare machines
- Rollback via `nixos-rebuild --rollback` is free
- sops-nix handles secrets natively in the NixOS module

**Cons:**
- Only works for Linux targets (NixOS or NixOS-via-nixos-anywhere)
- Requires building full NixOS system configs, not just apps
- Significantly higher Nix evaluation complexity
- Most Stackpanel users likely deploy to PaaS, not bare VMs

**When it makes sense:** teams running their own infrastructure (Hetzner, on-prem, AWS EC2 with NixOS AMIs). This is a valid and powerful story but probably not the primary use case.

---

### Approach C: Alchemy as Universal Backend

Alchemy is already used for Cloudflare + Neon + Upstash. It is a TypeScript-native IaC tool with a state engine, resource graph, and diff/preview semantics. The existing `infra/alchemy/index.ts` shows it can be the right level of abstraction for the project's current needs.

The idea: stackpanel generates or drives an Alchemy program from the deployment config, and `stackpanel deploy` becomes `alchemy run`.

```
stackpanel deploy web --env prod
  ≡ cd infra/alchemy && STAGE=prod bun run alchemy.run.ts
```

But more ambitiously, the Nix module system could generate Alchemy resource declarations:

```nix
# apps.web.deployment generates infra/gen/web.alchemy.ts:
apps.web.deployment = {
  backend = "alchemy";
  cloudflare.worker = {
    entrypoint = "src/index.ts";
    bindings = [ "DATABASE_URL" "BETTER_AUTH_SECRET" ];
  };
};
```

→ Generates:

```typescript
// infra/gen/web.alchemy.ts (auto-generated)
export const web = await cloudflare.Worker("web", {
  cwd: "${appPath}",
  bindings: resolveBindings(config.apps.web.deployment),
});
```

**Pros:**
- Alchemy handles state, diff, preview, rollback — no need to reinvent
- TypeScript is the right language for cloud API integrations
- Already proven in the project
- Alchemy's multi-cloud support (Cloudflare, AWS, Neon, Upstash) covers PaaS needs

**Cons:**
- Alchemy is still young; API stability risk
- Mixing Nix codegen → TypeScript → Alchemy adds a layer of indirection
- Non-JS deployment targets (bare VMs, NixOS) are not well-served by Alchemy
- State files need to be stored somewhere team-shared (S3, etc.) — already solved with `ALCHEMY_PASSWORD` + remote state

---

### Approach D: Fly.io as Primary PaaS Target

Looking at `deployment.fly.organization = "darkmatter"` and `bun.buildPhase = "bun run build:fly"` in the existing config, Fly.io appears to be the primary non-Cloudflare target. Fly is container-based, and the project has `container.enable = true` on the `web` app.

For Fly, the flow would be:
1. `nix build .#web` → produces the server bundle
2. Build OCI image from the derivation (via nix2container, which is already configured)
3. `fly deploy --image <image>` or `fly deploy` with the app's Dockerfile

```nix
apps.web.deployment = {
  backend = "fly";
  fly = {
    app = "stackpanel-web";
    region = "ord";
    secrets = [ "DATABASE_URL" "BETTER_AUTH_SECRET" ];
  };
};
```

```
stackpanel deploy web --env prod
  1. nix build .#web-container (OCI image via nix2container)
  2. docker push <registry>/web:<hash>
  3. fly secrets set --from-env=prod
  4. fly deploy --image <image>
```

**Pros:**
- Fly is a cohesive platform with good CLI
- nix2container → Fly is a clean pipeline: reproducible image, deterministic deploy
- Fly's secrets/env management is straightforward

**Cons:**
- Fly-specific; doesn't generalize
- nix2container requires a Linux builder (already handled via remote builder config)
- Container images are heavier than serverless bundles for web apps

---

### Approach E: Plugin Architecture with Protocol

Rather than choosing one backend, define a **deployment backend protocol** — a spec for what a backend must provide — and implement built-in backends plus allow plugin backends.

A backend is a Nix module (or a Go plugin) that provides:

```nix
# nix/stackpanel/modules/deploy/backends/fly/module.nix
{
  # What config fields this backend adds to apps.<name>.deployment.fly
  appOptions = { ... };

  # Command to run for deploy (receives resolved config as env/args)
  deployCommand = { app, environment, ... }: ''
    fly secrets set --app ${app.deployment.fly.app} \
      $(stackpanel vars export --env ${environment} --format fly)
    fly deploy --app ${app.deployment.fly.app}
  '';

  # What the backend produces (for status display)
  statusCommand = { app, ... }: "fly status --app ${app.deployment.fly.app} --json";
}
```

In the Go CLI, `stackpanel deploy` would:
1. Read `apps.<name>.deployment.backend`
2. Find the corresponding backend module
3. Execute its `deployCommand` with the resolved environment

**Pros:**
- Clean extension point for community backends
- Fits the existing `stackpanel.modules` registry pattern
- Backend authors own their logic

**Cons:**
- Protocol design is hard — too loose and backends are inconsistent, too strict and they can't express their semantics
- Shell string generation from Nix is fragile
- The Go CLI would need to invoke Nix to evaluate the backend module, adding latency

---

## 4. Recommendation

### Phase 1: Approach A (Thin Orchestrator)

For an initial implementation, the thin orchestrator model is the right choice:

1. **Formalize the existing `deployment` app option** — currently ad-hoc on `web`, make it a first-class option in `app-build/schema.nix` with a proper type
2. **Add `stackpanel deploy [app] [--env]` to the CLI** — reads config, resolves secrets via the existing secrets stack, calls the backend CLI
3. **Built-in backends:** `alchemy`, `fly`, `nixos-rebuild`, `colmena` — each is a Go function that knows how to invoke the tool
4. **Escape hatch:** `apps.<name>.deployment.command` for arbitrary commands

### Phase 2: Nix Derivations as First-Class Artifacts

After the basic flow works:

- For Fly + container backends: hook `nix build .#<app>-container` into the deploy pipeline
- For NixOS backends: generate NixOS module from app config + derivation
- For alchemy: pass the derivation's store path as an asset

### Phase 3: Status and Observability

- `stackpanel deploy status [app]` — query the backend for what's live
- Studio UI showing deployment status per app per environment
- Link to the Go agent's SSE stream for live deploy logs

---

## 5. Detailed Design: Phase 1

### 5.1 Config Schema

Extend `app-build/schema.nix` (or create a new `deploy/schema.nix`) with deployment fields:

```nix
# Per-app deployment options (serializable, proto-codegen-able)
deployment = {
  enable = sp.bool { default = false; index = 10; };

  backend = sp.enum {
    index = 11;
    values = [ "alchemy" "fly" "colmena" "nixos-rebuild" "custom" ];
    description = "Deployment backend to use";
    optional = true;
  };

  environment = sp.string {
    index = 12;
    description = "Default target environment (overridable via --env flag)";
    default = "prod";
  };

  command = sp.string {
    index = 13;
    description = "Override deploy command (escape hatch)";
    optional = true;
  };

  # Per-backend config stored as opaque attrs (not proto-codegen'd)
  # Backends have their own schema sub-modules
};
```

The backend-specific config (e.g., `deployment.fly.app`, `deployment.cloudflare.worker`) lives in sub-modules:

```nix
# nix/stackpanel/modules/deploy/backends/fly/schema.nix
{
  appName = sp.string { index = 1; description = "Fly app name"; };
  region = sp.string { index = 2; default = "ord"; };
  secrets = sp.string { index = 3; repeated = true; };
}
```

### 5.2 CLI Command

```
stackpanel deploy [app] [flags]

Flags:
  --env string       Target environment (default: app's deployment.environment)
  --dry-run          Show what would be deployed without executing
  --no-build         Skip nix build step (use cached derivation)
  --backend string   Override backend from config
  --verbose          Show full backend output
```

In Go (`apps/stackpanel-go/cmd/cli/deploy.go`):

```go
// Pseudocode
func deployApp(appName, env string, dryRun bool) error {
    // 1. Load config via nix eval
    cfg := nixconfig.LoadApp(appName)
    if !cfg.Deployment.Enable {
        return fmt.Errorf("app %s has no deployment config", appName)
    }

    // 2. Resolve environment (--env flag > config default > "prod")
    targetEnv := resolveEnv(env, cfg.Deployment.Environment)

    // 3. Resolve secrets for environment
    secrets, err := secrets.ResolveForEnv(appName, targetEnv)

    // 4. Delegate to backend
    backend := resolveBackend(cfg.Deployment.Backend)
    return backend.Deploy(DeployContext{
        App: cfg, Env: targetEnv, Secrets: secrets, DryRun: dryRun,
    })
}
```

### 5.3 Backend Implementations

**Alchemy backend:**
```go
type AlchemyBackend struct{}

func (b *AlchemyBackend) Deploy(ctx DeployContext) error {
    cmd := exec.Command("bun", "run", alchemyEntrypoint(ctx.App))
    cmd.Env = append(os.Environ(),
        "STAGE="+ctx.Env,
        // Inject resolved secrets as env vars
    )
    return cmd.Run()
}
```

**Fly backend:**
```go
type FlyBackend struct{}

func (b *FlyBackend) Deploy(ctx DeployContext) error {
    app := ctx.App.Deployment.Fly.AppName
    // 1. Set secrets
    flySecrets(app, ctx.Secrets)
    // 2. Build container if derivation available
    if ctx.App.Package != nil && !ctx.Flags.NoBuild {
        nixBuildContainer(ctx.App.Name)
    }
    // 3. Deploy
    return exec.Command("fly", "deploy", "--app", app).Run()
}
```

**NixOS/Colmena backend:**
```go
type ColmenaBackend struct{}

func (b *ColmenaBackend) Deploy(ctx DeployContext) error {
    // colmena.nix is expected at .stackpanel/deploy/colmena.nix
    colmenaFile := filepath.Join(stackpanelDir, "deploy/colmena.nix")
    target := ctx.App.Deployment.Colmena.Target // host name
    return exec.Command("colmena", "apply",
        "--on", target,
        "--hive", colmenaFile,
    ).Run()
}
```

### 5.4 Secrets at Deploy Time

This is the most complex piece. The existing secrets model (SOPS + chamber) is designed for dev-time injection. Deploy-time secret handling varies by backend:

| Backend | Mechanism |
|---|---|
| Cloudflare Workers | CF Secrets API (bindings in `wrangler.toml`) |
| Fly.io | `fly secrets set KEY=VALUE` |
| NixOS | sops-nix reads from `.age` files at activation |
| Custom | Environment variables injected into `command` subprocess |

For Phase 1, each backend is responsible for secret injection from the resolved SOPS data. The CLI provides a helper (`secrets.ResolveForEnv`) that returns `map[string]string` of decrypted values for a given app+environment.

A key design question: **should secrets ever be passed via the stackpanel CLI process, or should the CLI generate a one-time token / tempfile that the backend tool reads?** Passing secrets through env vars in the CLI process is fine for most cases but leaves them in process memory and potentially in shell history if commands are logged. A better pattern is:

```
stackpanel deploy web --env prod
  → writes secrets to temp file (chmod 600)
  → invokes backend with --env-file /tmp/stackpanel-deploy-<pid>.env
  → deletes temp file on exit (deferred)
```

### 5.5 Environment Promotion

One thing the thin orchestrator gains for free: environment promotion via the `--env` flag:

```
stackpanel deploy web --env staging   # deploy to staging
stackpanel deploy web --env prod      # promote to prod
```

The same deployment config is used; only the secret values and possibly backend-specific parameters (e.g., fly app names like `myapp-staging` vs `myapp-prod`) differ. This argues for parameterizing per-backend config by environment:

```nix
apps.web.deployment.fly = {
  app = {
    staging = "myapp-staging";
    prod = "myapp-prod";
  };
};
```

---

## 6. Trade-offs Summary

| Dimension | Thin Orchestrator (A) | Nix-Native (B) | Alchemy-as-Backend (C) | Plugin Protocol (E) |
|---|---|---|---|---|
| Implementation effort | Low | High | Medium | High |
| Fits existing project | ✓ | Partial | ✓ | Partial |
| Non-NixOS targets | ✓ | ✗ | ✓ | ✓ |
| NixOS targets | ✓ | ✓ | ✗ | ✓ |
| State management | Per-tool | Nix generations | Alchemy state | Per-backend |
| Uses Nix derivations | Optional | Central | Optional | Optional |
| Rollback story | Per-tool | nixos-rebuild --rollback | Alchemy destroy/redeploy | Per-backend |
| Secrets handling | Delegated | sops-nix | Alchemy.secret() | Per-backend |
| Extension point | No | No | No | Yes |
| UX consistency | Low | High (NixOS only) | High (JS targets) | Medium |

---

## 7. Open Questions

1. **Where does colmena.nix / nixops config live?** If stackpanel generates the NixOS deployment config, it needs a place to write it. Options: `.stackpanel/deploy/`, committed to repo, or generated at deploy time.

2. **Remote builds for containers:** nix2container requires Linux. The existing remote builder config handles this, but `stackpanel deploy` would need to verify the builder is reachable before attempting a container build. Should this be a preflight check?

3. **Deploy state:** "What version is deployed where?" is a cross-cutting concern. Each backend answers this differently. Should stackpanel maintain its own thin state file (`.stackpanel/state/deployments.json`) tracking last deploy per app per environment? This would enable `stackpanel deploy status` without querying backends.

4. **CI/CD integration:** The Go agent cannot be running in CI. Should `stackpanel deploy` work without the agent? Yes — the agent is only needed for the Studio UI. The CLI should be fully functional standalone.

5. **Preview environments:** The existing Alchemy config supports per-STAGE Neon branches and separate Fly apps. Should `stackpanel deploy --env preview/pr-42` be a first-class concept? This maps well to Alchemy's state model (separate state file per stage) but needs thought for NixOS backends.

6. **Relationship to `stackpanel infra`:** Should resource provisioning (creating the Fly app, the Neon database) be separated from artifact deployment (pushing the app)? The former is `alchemy run`; the latter is `fly deploy`. Keeping them separate makes rollback, partial failure, and day-2 operations easier to reason about.

7. **The `commands.build.package` path:** The `app-commands` module already allows a `commands.build.package` as a deployment artifact source. Should `stackpanel deploy` invoke `commands.build` first if no pre-built derivation is available?

---

## 8. Proposed Next Steps

1. Audit what `deployment.*` config already exists on apps in `config.nix` and normalize it
2. Design the `deployment` sub-schema as a proper SpField set in `deploy/schema.nix`
3. Implement `stackpanel deploy` in Go as a thin orchestrator (Approach A)
4. Start with two backends: `alchemy` (covers Cloudflare + Neon, what the project uses today) and `fly` (containers)
5. Wire the Nix derivation from `nix build .#<app>` into the Fly backend's container build step
6. Add `stackpanel deploy status` that reads last-deploy state from `.stackpanel/state/deployments.json`
7. Studio UI panel for deployment status per app (post-CLI)
