# Design: Exposing Apps as Flake Derivations

**Status**: Draft
**Date**: 2026-02-28

## Problem Statement

Stackpanel apps currently exist primarily as development-time entities: they get
ports, domains, process-compose entries, and dev commands, but they don't produce
first-class Nix derivations exposed through the project's flake. A user who runs
`nix build .#web` or `nix flake check` gets nothing unless they've manually
wired up derivations via `stackpanel.outputs` or the `commands` system.

We want apps to produce derivations automatically so that:

- `nix build .#web` builds the web app for distribution
- `nix flake check` runs app tests and lints
- Other flakes can consume `inputs.myproject.packages.${system}.web`
- CI pipelines can use standard Nix commands (`nix build`, `nix flake check`)
  without knowing about stackpanel internals
- Container builds (already partially supported) can reference these derivations

## Current State

### What already exists

1. **`app.commands`** (app-commands module): Per-app `build`/`dev`/`test`/`lint`/`format`
   commands that produce derivations routed to `stackpanel.outputs`,
   `stackpanel.checks`, or `stackpanel.flakeApps`. These require explicit
   configuration per app.

2. **Go module** (`modules/go/`): When `app.go.enable = true`, produces
   `stackpanel.go.packages.apps.<name>` via `buildGoApplication`. These are
   stored under a module-specific option, not directly in flake outputs.

3. **Bun module** (`modules/bun/`): When `app.bun.enable = true`, produces
   `stackpanel.bun.packages.apps.<name>` via `bun2nix.writeBunApplication`.
   Same pattern as Go -- module-specific option, not wired to flake outputs.

4. **`stackpanel.outputs`**: A generic `attrsOf (either package (attrsOf package))`
   option that gets routed to `packages` in the flake. Used by scripts,
   entrypoints, and app-commands, but not by the Go/Bun modules.

5. **Containers** (`containers/`): Per-app container images via
   `app.container.enable = true`. These reference app build artifacts but
   currently don't consume a standardized app derivation.

### Gaps

- **Go/Bun packages are siloed**: They live under `stackpanel.go.packages` and
  `stackpanel.bun.packages` respectively, not in flake `packages` output.
- **No automatic derivation**: Defining an app doesn't produce a buildable
  derivation unless you also enable the Go/Bun module AND manually wire outputs.
- **No standard "build" contract**: There's no uniform way to say "this app
  produces a derivation" regardless of runtime (Go, Bun, Cargo, Python, etc.).
- **`commands.build` is shell-oriented**: The app-commands `build` option
  wraps a shell command in `writeShellApplication`, which produces a script
  derivation, not a proper build artifact. It's meant for "run this build step",
  not "produce a distributable package".
- **Missing runtimes**: No Cargo/Rust, Python, or generic/custom builder support.

## Design Alternatives

### Alternative A: Unified `app.package` option

Add a single `package` option to every app that holds the derivation representing
the built artifact. Language modules (Go, Bun, Cargo, etc.) set it automatically
when enabled. Users can also set it manually for unsupported runtimes.

```nix
# Auto-set by the Go module when go.enable = true:
stackpanel.apps.server.package = mkGoPackage "server" app;

# Auto-set by the Bun module when bun.enable = true:
stackpanel.apps.web.package = mkBunPackage "web" app;

# Manual override or custom builder:
stackpanel.apps.custom-service.package = pkgs.rustPlatform.buildRustPackage { ... };
```

The core system then collects all non-null `app.package` values and routes them
to `stackpanel.outputs`, which flows to `packages.<name>` in the flake.

**Flake output mapping:**

| App config | Flake output | Access |
|---|---|---|
| `app.package` | `packages.<name>` | `nix build .#web` |
| `app.checkDerivation` | `checks.<name>` | `nix flake check` |
| `app.package` (with exe) | `apps.<name>` | `nix run .#web` |

**Pros:**
- Single, clear point of truth for "what does this app build to?"
- Language modules just set one option; the core handles routing
- Easy for users to understand and override
- Composable: container module can reference `app.package`
- Low complexity in the core; language modules own the builder logic

**Cons:**
- Doesn't capture test/lint/format derivations (need separate options)
- Language modules must carefully use `mkDefault`/`mkOverride` priorities
  to allow user overrides
- The `package` is a single derivation; some apps may produce multiple
  artifacts (e.g., server + worker binary from the same source)

### Alternative B: Extend `app.commands` to be the standard interface

Make `app.commands.build.package` the canonical way to expose an app derivation.
Language modules would set `commands.build.package` instead of a separate option.
The existing app-commands module already routes `commands.build` to
`packages.<name>`.

```nix
# Go module sets:
stackpanel.apps.server.commands.build.package = mkGoPackage "server" app;

# Bun module sets:
stackpanel.apps.web.commands.build.package = mkBunPackage "web" app;

# User can set shell-based build:
stackpanel.apps.legacy.commands.build = {
  command = "make build";
  runtimeInputs = [ pkgs.gnumake ];
};
```

**Pros:**
- Reuses existing infrastructure (app-commands module already works)
- Natural fit: `commands.build` already maps to `packages.<name>`
- `commands.test`, `commands.lint`, etc. already map to checks
- No new options needed; just wire language modules into existing ones

**Cons:**
- `commands` is a module that may not be loaded; creates ordering dependency
- The `commands` abstraction mixes shell scripts and derivations in a
  slightly awkward way (both `command` string and `package` derivation share
  the same option namespace)
- Language modules would need to depend on the app-commands module
- Less discoverable: users need to know to look at `commands.build.package`
  rather than a top-level `package` option

### Alternative C: Per-runtime derivation options with automatic aggregation

Each language module defines its own per-app derivation option (as today),
but a new core aggregator automatically collects them into `stackpanel.outputs`.

```nix
# Go module exposes (as today):
config.stackpanel.go.packages.apps.server = mkGoPackage ...;

# Bun module exposes (as today):
config.stackpanel.bun.packages.apps.web = mkBunPackage ...;

# New: core aggregator collects into outputs
config.stackpanel.outputs =
  (cfg.go.packages.apps or {})
  // (cfg.bun.packages.apps or {})
  // (cfg.cargo.packages.apps or {})
  // ...;
```

**Pros:**
- Minimal change to existing module structure
- Each module retains full control of its packaging logic
- No new per-app options needed

**Cons:**
- Aggregator must know about every language module (not extensible)
- No standard interface for external/third-party modules
- Siloed: `nix eval .#legacyPackages.stackpanelFullConfig.go.packages.apps`
  still required for programmatic access to the Go-specific derivation
- No obvious place for users to add packages for unsupported runtimes
- Doesn't work for external modules (e.g., a community Rust module)

### Alternative D: Typed `app.builders` with presets

Introduce a builder abstraction that captures the recipe for turning app source
into a derivation. Presets for common stacks (bun, go, cargo, npm, python) would
be provided. The builder is a function `appConfig -> derivation`.

```nix
stackpanel.apps.web = {
  path = "apps/web";
  builder = stackpanel.builders.bun {
    buildPhase = "bun run build";
    startScript = "bun run start";
  };
  # Or, shorthand when using a known type:
  type = "bun";  # auto-selects builder
};
```

The builder would produce:
- `app.package`: The built derivation
- `app.checkDerivation`: Test runner derivation
- `app.devCommand`: Dev server command

**Pros:**
- Declarative and composable
- Presets make common cases zero-config
- Custom builders are just functions
- Clean separation: builder produces derivations, core routes them

**Cons:**
- Significant new abstraction; higher design/implementation cost
- Presets must cover enough configuration surface to be useful
  (risk of "preset doesn't do what I need" leading to workarounds)
- Overlaps with existing `tooling`, `commands`, and language-specific
  options; migration path is complex
- Builders as functions don't compose well with the NixOS module system
  (can't `mkMerge` a function)

## Recommended Approach: Alternative A with elements of B

The recommended design combines Alternative A (unified `app.package`) with
the existing `commands` infrastructure from Alternative B for test/lint/format.

### Core changes

#### 1. Add `package` and `check` options to the app submodule

In `core/options/apps.nix`, add to `nixAppOptionsModule`:

```nix
package = lib.mkOption {
  type = lib.types.nullOr lib.types.package;
  default = null;
  description = ''
    The Nix derivation representing this app's build artifact.

    When set (either manually or by a language module like Go/Bun),
    the derivation is automatically exposed as:
      - packages.<name>  (nix build .#<name>)
      - apps.<name>      (nix run .#<name>, if the package has a main binary)

    Language modules set this automatically:
      - go.enable = true   -> buildGoApplication
      - bun.enable = true  -> bun2nix.writeBunApplication

    Users can override or set manually for custom build systems.
  '';
  example = lib.literalExpression "pkgs.buildGoApplication { ... }";
};

checkPackage = lib.mkOption {
  type = lib.types.nullOr lib.types.package;
  default = null;
  description = ''
    A derivation that runs this app's tests as a Nix build.
    Exposed as checks.<name> (runs during `nix flake check`).
    Language modules set this automatically when possible.
  '';
};
```

#### 2. Automatically route packages to flake outputs

In `core/options/apps.nix`, add a config block:

```nix
config.stackpanel.outputs = lib.mkMerge (
  lib.mapAttrsToList (name: app:
    lib.optionalAttrs (app.package != null) {
      ${name} = app.package;
    }
  ) config.stackpanel.apps
);

config.stackpanel.checks = lib.mkMerge (
  lib.mapAttrsToList (name: app:
    lib.optionalAttrs (app.checkPackage != null) {
      "${name}-test" = app.checkPackage;
    }
  ) config.stackpanel.apps
);

config.stackpanel.flakeApps = lib.mkMerge (
  lib.mapAttrsToList (name: app:
    lib.optionalAttrs (app.package != null) {
      ${name} = {
        type = "app";
        program = lib.getExe app.package;
      };
    }
  ) config.stackpanel.apps
);
```

#### 3. Language modules set `app.package`

**Go module** (modify `modules/go/module.nix`):

```nix
# Instead of (or in addition to) stackpanel.go.packages:
stackpanel.apps = lib.mapAttrs (name: app: {
  package = lib.mkDefault (mkGoPackage name app);
  checkPackage = lib.mkDefault (mkGoTests name app);
}) goApps;
```

**Bun module** (modify `modules/bun/module.nix`):

```nix
stackpanel.apps = lib.mapAttrs (name: app: {
  package = lib.mkDefault (mkBunPackage name app);
}) bunApps;
```

Using `lib.mkDefault` ensures users can override the derivation.

#### 4. Interaction with `commands`

The `app.commands.build.package` and `app.package` should be kept consistent.
Two approaches:

**Option 4a: `commands.build` feeds `package` (preferred)**

If the user sets `commands.build.package`, it becomes the `package`:

```nix
# In app-commands module or core:
config.stackpanel.apps = lib.mapAttrs (name: app:
  lib.optionalAttrs (app.commands.build.package or null != null) {
    package = lib.mkDefault app.commands.build.package;
  }
) cfg.apps;
```

This means `commands.build.package` and language module auto-set are both
sources for `app.package`, with the language module winning by default and
the user's explicit `commands.build.package` having higher priority.

**Option 4b: `package` is independent of `commands`**

`commands` remains a separate system for shell-oriented operations. The
`package` option is purely for the build artifact derivation. No automatic
link between them.

Recommendation: **4a** - unifying them reduces confusion. A user should only
need to set the package in one place.

### Semi-automatic packaging for common runtimes

#### Bun/npm apps

When `app.type = "bun"` (or when `bun.enable = true`), the Bun module
automatically produces a package using `bun2nix.writeBunApplication`.

Required from the user: nothing beyond what's already needed.

The module infers:
- `src` from `app.path`
- `packageJson` from `app.path + "/package.json"`
- `bunDeps` from the nearest `bun.nix` lockfile
- `buildPhase` from `app.bun.buildPhase` (defaults to `"bun run build"`)
- `startScript` from `app.bun.startScript` (defaults to `"bun run start"`)

#### Go apps

When `app.type = "go"` (or when `go.enable = true`), the Go module
already produces a package via `buildGoApplication`. The only change is
routing it to `app.package`.

#### Cargo/Rust apps (new)

A new `modules/cargo/` module would handle Rust apps:

```nix
stackpanel.apps.my-service = {
  path = "apps/my-service";
  cargo.enable = true;
  # Optional overrides:
  cargo.features = [ "production" ];
};
```

The module would use `pkgs.rustPlatform.buildRustPackage` or
`crane`/`naersk` (configurable). It would:
- Detect `Cargo.toml` in `app.path`
- Use `cargoHash` or `cargoLock` for dependency pinning
- Set `app.package` automatically

#### Python apps (new)

```nix
stackpanel.apps.ml-service = {
  path = "apps/ml";
  python.enable = true;
  python.format = "pyproject"; # or "setuptools"
};
```

Would use `pkgs.python3Packages.buildPythonApplication` or
`poetry2nix`/`pyproject.nix`.

#### Generic/custom apps

For runtimes without a module, users set `package` directly:

```nix
stackpanel.apps.legacy = {
  path = "apps/legacy";
  package = pkgs.stdenv.mkDerivation {
    name = "legacy";
    src = ./apps/legacy;
    buildPhase = "make";
    installPhase = "mkdir -p $out/bin && cp build/app $out/bin/legacy";
  };
};
```

Or use `commands.build.package` if they prefer the commands interface.

### Flake output summary

After implementation, a project with these apps:

```nix
apps = {
  web = { path = "apps/web"; bun.enable = true; };
  api = { path = "apps/api"; go.enable = true; };
  docs = { path = "apps/docs"; type = "bun"; };
  custom = { path = "apps/custom"; package = myCustomDrv; };
};
```

Would produce these flake outputs:

```
packages.x86_64-linux.web           # bun2nix.writeBunApplication
packages.x86_64-linux.api           # buildGoApplication
packages.x86_64-linux.docs          # bun2nix.writeBunApplication
packages.x86_64-linux.custom        # user-provided derivation

checks.x86_64-linux.api-test        # go test
checks.x86_64-linux.web-test        # bun test (if configured)

apps.x86_64-linux.web               # nix run .#web
apps.x86_64-linux.api               # nix run .#api
```

### Lazy evaluation considerations

App packages must be lazily evaluated so that:

1. `nix develop` doesn't build all apps (entering the devshell should be fast)
2. `nix build .#web` only evaluates the web app's derivation
3. A build failure in one app doesn't prevent building others

This is naturally handled by Nix's lazy evaluation as long as we use
`lib.mapAttrs` and attribute access rather than `lib.mapAttrsToList` in
the output routing (which would force evaluation of all values).

The current `stackpanel.outputs` routing in `nix/flake/default.nix` already
handles this correctly:

```nix
directPkgs = lib.filterAttrs (_: v: lib.isDerivation v) spOutputs;
```

However, `lib.isDerivation` forces evaluation of each value to check if it's
a derivation. We should consider using `lib.types.package` typing to avoid
this, or accept the minor evaluation cost (it only evaluates the top-level
attrset, not the derivation build itself).

### Migration path

1. **Phase 1**: Add `package` and `checkPackage` options to app submodule,
   add automatic routing to `stackpanel.outputs`/`checks`/`flakeApps`.
   No breaking changes.

2. **Phase 2**: Modify Go module to set `app.package` via `lib.mkDefault`.
   Keep `stackpanel.go.packages` as a secondary accessor for backwards compat.

3. **Phase 3**: Modify Bun module similarly. Both modules now auto-expose
   packages through the flake.

4. **Phase 4**: Wire `commands.build.package` -> `app.package` connection.
   Users who set `commands.build.package` get automatic flake output.

5. **Phase 5** (optional): Add Cargo/Python modules. Deprecate
   `stackpanel.go.packages` / `stackpanel.bun.packages` in favor of
   `app.package`.

### Naming and conflicts

App names must not conflict with other `stackpanel.outputs` entries
(e.g., `stackpanel-scripts`, entrypoint packages). The routing should use
a `lib.mkDefault` priority so that explicit `stackpanel.outputs.web = ...`
overrides the auto-generated one.

If an app's name conflicts with a non-app output, the user gets a Nix
merge error. This is acceptable since app names and output names are both
under user control.

### Container integration

The containers module (`containers/module.nix`) currently builds container
images independently. With `app.package`, it can reference the pre-built
derivation:

```nix
# In containers module, when building for an app:
app = config.stackpanel.apps.${name};
appPackage = app.package;  # Use the unified derivation
```

This avoids duplicate builds and ensures the container contains exactly
the same artifact as `nix build .#<name>`.

## Summary of trade-offs

| Aspect | This design (A+B) | Alt C (aggregator) | Alt D (builders) |
|---|---|---|---|
| User-facing simplicity | High - one `package` option | Medium | High but different mental model |
| Implementation cost | Low-medium | Low | High |
| Extensibility | High - any module can set `package` | Low - hardcoded list | High but complex |
| Backwards compat | Full | Full | Breaking |
| Custom runtime support | Good - set `package` directly | Poor | Good via custom builder |
| Interaction with `commands` | Clean via option 4a | Independent | Overlapping |
| New module cost | Low - just set `package` | Low + update aggregator | Medium - implement builder interface |

## Open Questions

1. **Should `app.package` be set even when the app has no buildable artifact?**
   For example, a docs app that's only a dev server. Recommendation: no, leave
   it null. Only set it when there's a meaningful build output.

2. **Should we auto-detect `app.type` from files in `app.path`?** E.g., detect
   `Cargo.toml` -> `cargo`, `go.mod` -> `go`, `package.json` + `bun.lock` ->
   `bun`. This would enable truly zero-config packaging but adds complexity
   and can misfire. Recommendation: defer to a later phase; explicit
   `type` or `<runtime>.enable` is clearer.

3. **Should `nix run .#<name>` run the dev server or the built artifact?**
   Recommendation: the built artifact (production mode). Dev mode is
   accessed via `nix run .#<name>-dev` or process-compose.

4. **What about monorepo workspace apps that share dependencies?** Bun/npm
   workspaces may need the root `node_modules` during build. The Bun module
   already handles this by detecting per-app vs root `bun.nix`. This should
   continue to work with the unified `package` option.

5. **Should we expose a `packages.all` or `packages.default` that builds all
   apps?** Could be useful for CI. Recommendation: yes, add a
   `packages.default = pkgs.symlinkJoin { ... }` that combines all app
   packages. This gives `nix build` (no argument) a useful default.
