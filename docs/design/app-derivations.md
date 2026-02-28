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
- The Studio UI can display and configure build settings for apps

## Two Cross-Cutting Concerns

Before evaluating alternatives, we must address two dimensions that cut across
all designs:

### 1. UI introspectability

Stackpanel has a web-based Studio UI backed by a Go agent. The agent reads
configuration via `nix eval --json` on the **serializable** subset of config
(`filterSerializable` in `lib/serialize.nix`), and writes changes back by
patching `.stackpanel/config.nix` via the `PatchNixData` RPC.

The serialization boundary is strict:

| Serializable (UI can read/edit) | Non-serializable (Nix-only) |
|---|---|
| Strings, bools, ints, floats | Derivations (`type == "derivation"`) |
| Lists of scalars | Functions/lambdas |
| Attrsets of scalars | Module system internals (`_type`) |
| Proto-schema fields (`field.nix`) | Functors (`__functor`) |
| `app.go.mainPackage = "."` | `app.package = mkGoPackage ...` |

This means: **any option of type `lib.types.package` is invisible to the UI**.
The UI can never display a derivation, offer to configure one, or know whether
one exists. It can only work with the structured, scalar options that *produce*
a derivation.

This has major implications for the design: we need the "build recipe" (the
structured fields that describe how to build) to be UI-visible, even if the
resulting derivation is Nix-only. The question is whether the recipe lives
in per-runtime options (current approach) or a unified builder abstraction.

### 2. Sources and dependencies

Building a derivation requires knowing:

- **Where is the source code?** (`src` in Nix terms)
- **What layout?** Monorepo workspace vs standalone app
- **Where are the dependencies?** Lockfiles: `gomod2nix.toml`, `bun.nix`,
  `Cargo.lock`, `poetry.lock`, etc.
- **What source filtering?** Which files to include in the Nix store
- **What build inputs?** Runtime dependencies, native build tools

Currently, this information is **mostly implicit**, inferred by convention
and `builtins.pathExists` checks:

```
# Go module (modules/go/module.nix):
hasPerAppGoMod = builtins.pathExists (repoRoot + "/${appPath}/go.mod");
src = if hasPerAppGoMod then repoRoot + "/${appPath}" else repoRoot;
gomod2nixPath = if hasPerAppGomod2nix then
  repoRoot + "/${appPath}/gomod2nix.toml"
else repoRoot + "/gomod2nix.toml";

# Bun module (modules/bun/module.nix):
hasPerAppBunNix = builtins.pathExists (repoRoot + "/${appPath}/bun.nix");
src = if hasPerAppBunNix then repoRoot + "/${appPath}" else repoRoot;
```

**What's currently explicit** (configured in `config.nix`):
- `app.path` -- relative directory of the app
- `app.go.mainPackage` -- Go entrypoint (e.g., `"./cmd/server"`)
- `app.bun.buildPhase` -- build command (e.g., `"bun run build"`)
- `app.bun.startScript` -- start command for production
- `app.go.ldflags` -- linker flags

**What's currently implicit** (convention + file detection):
- Source layout (workspace vs per-app) -- detected via `go.mod` / `bun.nix` presence
- Dependency lockfile location -- derived from layout
- Source tree root -- always `../../../..` (relative to module file)
- Build output path (containers) -- defaults to `${path}/.output`
- Source filtering -- none; entire repo or entire app dir is copied

Each design alternative must address how these inputs are specified.

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
- **Source/dep specification is implicit**: No explicit options for source
  layout, lockfile paths, or source filtering.
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

**Sources and deps**: Unchanged from current. Each language module continues to
infer source layout and lockfile paths from `app.path` and convention. The
`package` option is just the output derivation; it says nothing about how it was
built. Users who set `package` directly must handle sources themselves.

**UI visibility**: The `package` option itself is invisible to the UI (it's a
derivation). The UI can only see the per-runtime fields that produce it
(`go.mainPackage`, `bun.buildPhase`, etc.). The UI has no unified view of
"does this app have a build?" -- it must know about each runtime's specific
`enable` flag.

**Pros:**
- Single, clear Nix-level point of truth for "what does this app build to?"
- Language modules just set one option; the core handles routing
- Easy for Nix users to understand and override
- Composable: container module can reference `app.package`
- Low complexity in the core; language modules own the builder logic

**Cons:**
- UI-opaque: the Studio can't show a unified "Build" panel for all apps
- UI must hardcode knowledge of each runtime to show build configuration
- Sources/deps stay implicit; no way for the UI to show "source layout:
  workspace" or "lockfile: gomod2nix.toml"
- Manual `package` setting requires Nix knowledge; can't be done from UI

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

**Sources and deps**: Same as A -- implicit, unchanged. The `commands` layer
doesn't model sources at all.

**UI visibility**: `commands.build.command` (a string) is serializable and
UI-visible, but `commands.build.package` (a derivation) is not. The UI could
show that a build command exists but can't introspect the derivation. Slightly
better than A because `commands` have a `description` field.

**Pros:**
- Reuses existing infrastructure (app-commands module already works)
- Natural fit: `commands.build` already maps to `packages.<name>`
- `commands.test`, `commands.lint`, etc. already map to checks
- No new options needed; just wire language modules into existing ones

**Cons:**
- `commands` is a module that may not be loaded; creates ordering dependency
- The `commands` abstraction mixes shell scripts and derivations awkwardly
- Language modules would need to depend on the app-commands module
- Less discoverable: users need to know `commands.build.package` rather than
  a top-level option
- Sources/deps still implicit and invisible to UI

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
  // (cfg.cargo.packages.apps or {});
```

**Sources and deps**: Unchanged -- each module handles its own.

**UI visibility**: Same limitations as today. Each module's structured options
are visible, but there's no unified view.

**Pros:**
- Minimal change to existing module structure
- Each module retains full control of its packaging logic
- No new per-app options needed

**Cons:**
- Aggregator must know about every language module (not extensible)
- No standard interface for external/third-party modules
- No obvious place for users to add packages for unsupported runtimes
- Doesn't work for external modules (e.g., a community Rust module)
- Sources/deps still implicit

### Alternative D: Structured `app.build` options with runtime presets

Introduce a structured, serializable `build` submodule on every app that
captures the build recipe in UI-visible terms. Language modules provide
presets that fill in defaults. The build recipe is used by the module to
compute a derivation that gets routed to flake outputs.

```nix
stackpanel.apps.web = {
  path = "apps/web";
  type = "bun";

  build = {
    enable = true;

    # Source configuration (common across all runtimes)
    src = {
      root = null;       # null = infer from path (default)
      layout = null;     # null = auto-detect; or "workspace" | "standalone"
      filter = null;     # null = default; or list of globs to include
    };

    # Dependency lockfile (runtime-specific but structurally uniform)
    deps = {
      lockfile = null;   # null = auto-detect; or explicit path
    };

    # Output configuration
    output = {
      binary-name = null; # Override output name
      version = "0.1.0";
    };
  };

  # Runtime-specific options (existing, set by language modules)
  bun = {
    enable = true;
    buildPhase = "bun run build";
    startScript = "bun run start";
  };
};
```

The language module reads `app.build.*` + `app.bun.*` (or `app.go.*`) and
produces a derivation, setting it on an internal `app._derivation` or
routing it directly through `stackpanel.outputs`.

**Sources and deps**: Explicitly modeled! `build.src.root`, `build.src.layout`,
`build.deps.lockfile` are scalar options that the UI can read and modify.
Language modules still auto-detect defaults via `builtins.pathExists`, but
users can override from the UI.

**UI visibility**: Excellent. The `build` submodule is entirely scalar/structured:

```
App: web
  Build: enabled
    Source: apps/web (workspace layout, auto-detected)
    Deps lockfile: bun.nix (auto-detected)
    Output: web v0.1.0
  Runtime: bun
    Build phase: bun run build
    Start script: bun run start
```

The UI can show a unified "Build" panel for any app regardless of runtime,
with runtime-specific sections below it.

**How a language module uses this:**

```nix
# In bun/module.nix:
mkBunPackage = name: app:
  let
    buildCfg = app.build;
    bunCfg = app.bun;
    repoRoot = ../../../..;

    # Use explicit src.root if set, otherwise infer from layout
    layout = buildCfg.src.layout or (
      if builtins.pathExists (repoRoot + "/${app.path}/bun.nix")
      then "standalone"
      else "workspace"
    );

    src = if buildCfg.src.root != null
      then repoRoot + "/${buildCfg.src.root}"
      else if layout == "standalone"
        then repoRoot + "/${app.path}"
        else repoRoot;

    lockfile = if buildCfg.deps.lockfile != null
      then repoRoot + "/${buildCfg.deps.lockfile}"
      else if layout == "standalone"
        then repoRoot + "/${app.path}/bun.nix"
        else repoRoot + "/bun.nix";

    pname = buildCfg.output.binary-name or name;
    version = buildCfg.output.version;
  in
  pkgs.bun2nix.writeBunApplication {
    inherit pname version src;
    buildPhase = bunCfg.buildPhase;
    startScript = bunCfg.startScript;
    bunDeps = pkgs.bun2nix.fetchBunDeps { bunNix = lockfile; };
  };
```

**Pros:**
- UI can display and configure build settings for any app
- Source and dependency specification is explicit and overridable
- Unified "Build" panel possible in Studio regardless of runtime
- Auto-detection is still the default; explicit config is the override
- Proto schema can model the `build` submodule → codegen for Go/TS types
- External modules can participate (they just read `app.build.*`)
- Common fields (src, deps, output) are factored out; runtime-specific
  fields stay in their module (`bun.*`, `go.*`)

**Cons:**
- New abstraction layer -- more options to document and maintain
- Risk of abstraction mismatch: `build.src.filter` might mean different things
  to different builders
- Language modules now read from two places (`app.build.*` and `app.go.*`)
- Must carefully handle the auto-detect-vs-explicit priority
- Higher implementation cost than A

## Recommended Approach: Hybrid of A and D

The recommended design uses the **structured build recipe** from Alternative D
for UI visibility and source/dep specification, combined with the **unified
`package` option** from Alternative A as the Nix-level output. This gives us
both: the UI can show and configure build settings, and Nix users can access
or override the derivation directly.

### Architecture: Two Layers

```
┌────────────────────────────────────────────────────────────┐
│  UI-visible layer (serializable, proto-schema-backed)      │
│                                                            │
│  app.build.enable        = true                            │
│  app.build.src.layout    = "workspace"  (auto-detected)    │
│  app.build.deps.lockfile = null         (auto-detected)    │
│  app.build.output.version = "0.1.0"                        │
│  app.bun.buildPhase      = "bun run build"                 │
│  app.bun.startScript     = "bun run start"                 │
│                                                            │
├────────────────────────────────────────────────────────────┤
│  Nix-only layer (derivations, not serializable)            │
│                                                            │
│  app.package       = <derivation>  (set by bun module)     │
│  app.checkPackage  = <derivation>  (set by bun module)     │
│                                                            │
│  → routed to packages.<name>, checks.<name>, apps.<name>   │
└────────────────────────────────────────────────────────────┘
```

The UI sees and edits the top layer. Language modules read the top layer and
produce the bottom layer. The core routes the bottom layer to flake outputs.

Users who need full Nix control bypass the top layer entirely:

```nix
stackpanel.apps.legacy = {
  path = "apps/legacy";
  # Skip the build recipe, set the derivation directly:
  package = pkgs.stdenv.mkDerivation { ... };
};
```

### Core changes

#### 1. Add `build` submodule to the app options

In `core/options/apps.nix`, add to `nixAppOptionsModule`:

```nix
build = {
  enable = lib.mkEnableOption "Nix-based packaging for this app" // {
    default = false;
  };

  src = {
    root = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Source root path, relative to the repo root.
        If null, inferred from `path` and `layout`:
        - standalone: uses `path` as root
        - workspace: uses repo root
      '';
      example = "apps/web";
    };

    layout = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum [ "workspace" "standalone" ]);
      default = null;
      description = ''
        Source layout strategy.
        - workspace: app is part of a monorepo; build from repo root
        - standalone: app has its own dependency manifest; build from app dir
        If null, auto-detected by checking for per-app lockfiles.
      '';
    };

    include = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Glob patterns for source filtering. If empty, includes everything.
        Applied via lib.fileset or cleanSourceWith.
        Example: [ "src/**" "package.json" "tsconfig.json" ]
      '';
    };
  };

  deps = {
    lockfile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Path to the dependency lockfile, relative to repo root.
        If null, auto-detected based on runtime and layout:
        - Go workspace: gomod2nix.toml
        - Go standalone: <path>/gomod2nix.toml
        - Bun workspace: bun.nix
        - Bun standalone: <path>/bun.nix
      '';
      example = "apps/web/bun.nix";
    };
  };

  output = {
    binary-name = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Override the output binary/package name.
        Defaults to the app name.
      '';
    };

    version = lib.mkOption {
      type = lib.types.str;
      default = "0.1.0";
      description = "Version string for the built package.";
    };
  };
};
```

These fields are all scalar types (string, bool, enum, list-of-string), so
they serialize to JSON and are UI-editable. The `build` submodule should also
be modeled in a proto schema (`db/schemas/app-build.proto.nix`) so it gets
proper codegen for the Go agent and TypeScript UI types.

#### 2. Add `package` and `checkPackage` (Nix-only)

Also in `nixAppOptionsModule`:

```nix
package = lib.mkOption {
  type = lib.types.nullOr lib.types.package;
  default = null;
  description = ''
    The Nix derivation for this app's build artifact.
    Set automatically by language modules (Go, Bun, etc.) when
    build.enable = true. Can be set manually for custom builds.

    Automatically exposed as:
      - packages.<name>  (nix build .#<name>)
      - apps.<name>      (nix run .#<name>)
  '';
};

checkPackage = lib.mkOption {
  type = lib.types.nullOr lib.types.package;
  default = null;
  description = ''
    Test derivation. Exposed as checks.<name>-test.
  '';
};
```

These are `lib.types.package` -- they'll be filtered out by `filterSerializable`
and never reach the UI. That's correct; the UI interacts with `build.*` instead.

#### 3. Automatic routing to flake outputs

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

#### 4. Language modules read `build.*` and set `package`

**Go module** (modify `modules/go/module.nix`):

```nix
# Filter to Go apps with build enabled
goAppsWithBuild = lib.filterAttrs
  (name: app: (app.go.enable or false) && (app.build.enable or false))
  cfg.apps;

# Set package for each
stackpanel.apps = lib.mapAttrs (name: app: {
  package = lib.mkDefault (mkGoPackage name app);
  checkPackage = lib.mkDefault (mkGoTests name app);
}) goAppsWithBuild;
```

Inside `mkGoPackage`, the module reads from `app.build.src.*` and
`app.build.deps.*` when they're set, falling back to current auto-detection
when they're null:

```nix
mkGoPackage = name: app:
  let
    buildCfg = app.build;
    goCfg = app.go;
    repoRoot = ../../../..;

    # Layout: explicit > auto-detected
    layout = buildCfg.src.layout or (
      if builtins.pathExists (repoRoot + "/${app.path}/go.mod")
      then "standalone"
      else "workspace"
    );

    # Source root: explicit > inferred from layout
    src = if buildCfg.src.root != null
      then repoRoot + "/${buildCfg.src.root}"
      else if layout == "standalone"
        then repoRoot + "/${app.path}"
        else repoRoot;

    # Lockfile: explicit > inferred from layout
    gomod2nixPath = if buildCfg.deps.lockfile != null
      then repoRoot + "/${buildCfg.deps.lockfile}"
      else if layout == "standalone" &&
              builtins.pathExists (repoRoot + "/${app.path}/gomod2nix.toml")
        then repoRoot + "/${app.path}/gomod2nix.toml"
        else repoRoot + "/gomod2nix.toml";

    pname = buildCfg.output.binary-name or goCfg.binaryName or name;
    version = buildCfg.output.version;
  in
  pkgs.buildGoApplication {
    inherit pname version src;
    modules = gomod2nixPath;
    subPackages = if layout == "standalone" then [ "." ] else [ app.path ];
    ldflags = [ "-s" "-w" ] ++ goCfg.ldflags;
    # ...
  };
```

**Bun module** follows the same pattern.

#### 5. Interaction with `commands`

`app.commands.build.package` and `app.package` are connected:

```nix
# If commands.build.package is set but app.package is not, use it:
config.stackpanel.apps = lib.mapAttrs (name: app:
  let cmds = app.commands or null; in
  lib.optionalAttrs
    (cmds != null && cmds.build or null != null &&
     cmds.build.package or null != null && app.package == null)
    { package = lib.mkDefault cmds.build.package; }
) cfg.apps;
```

Priority order (highest wins):
1. User sets `app.package = ...` explicitly
2. Language module sets via `lib.mkDefault`
3. `commands.build.package` sets via `lib.mkDefault` (lower priority)

#### 6. `build.enable` auto-activation

To minimize boilerplate, `build.enable` is automatically set to `true` when
a language module is enabled:

```nix
# In go/module.nix:
stackpanel.apps = lib.mapAttrs (name: app: {
  build.enable = lib.mkDefault true;
}) goApps;

# In bun/module.nix:
stackpanel.apps = lib.mapAttrs (name: app: {
  build.enable = lib.mkDefault true;
}) bunApps;
```

Users who want the language module for dev tooling but NOT the package can
set `build.enable = false` explicitly.

### How source filtering works per runtime

#### Go

| Field | Default (auto-detect) | Explicit override |
|---|---|---|
| `src.layout` | `builtins.pathExists "${path}/go.mod"` → standalone; else workspace | `"standalone"` or `"workspace"` |
| `src.root` | standalone: `path`; workspace: repo root | Any repo-relative path |
| `deps.lockfile` | standalone: `${path}/gomod2nix.toml`; workspace: `gomod2nix.toml` | Any repo-relative path |
| `src.include` | Everything in src root | `["cmd/**" "internal/**" "go.mod" "go.sum"]` |

#### Bun

| Field | Default (auto-detect) | Explicit override |
|---|---|---|
| `src.layout` | `builtins.pathExists "${path}/bun.nix"` → standalone; else workspace | `"standalone"` or `"workspace"` |
| `src.root` | standalone: `path`; workspace: repo root | Any repo-relative path |
| `deps.lockfile` | standalone: `${path}/bun.nix`; workspace: `bun.nix` | Any repo-relative path |
| `src.include` | Everything in src root | `["src/**" "package.json" "tsconfig.json"]` |

#### Cargo (future)

| Field | Default (auto-detect) | Explicit override |
|---|---|---|
| `src.layout` | `builtins.pathExists "${path}/Cargo.toml"` → standalone; else workspace | Same |
| `deps.lockfile` | `Cargo.lock` (location depends on layout) | Any repo-relative path |

### What the UI sees

With this design, the Studio UI can present a unified build panel:

```
┌─────────────────────────────────────────────────┐
│ App: web                                        │
│ Type: bun                                       │
├─────────────────────────────────────────────────┤
│ Build Settings                                  │
│                                                 │
│ ☑ Enable Nix packaging                         │
│                                                 │
│ Source                                          │
│   Layout:    [auto-detect ▾]  (detected: workspace) │
│   Root:      [auto ▾]        (resolved: .)     │
│   Include:   [default - all files]             │
│                                                 │
│ Dependencies                                    │
│   Lockfile:  [auto ▾]        (resolved: bun.nix) │
│                                                 │
│ Output                                          │
│   Name:      [web]                              │
│   Version:   [0.1.0]                            │
│                                                 │
├─────────────────────────────────────────────────┤
│ Bun Settings                                    │
│   Build phase:  [bun run build]                 │
│   Start script: [bun run start]                 │
│   Runtime env:  {PORT: "3000"}                  │
└─────────────────────────────────────────────────┘
```

The "resolved" values can be computed by the Go agent at eval time
and included in the serialized config alongside the null/auto values.
This lets the UI show what auto-detection chose.

### Computed build metadata for the UI

To show auto-detected values in the UI, add a read-only computed section
(similar to `appsComputed` for ports):

```nix
config.stackpanel.appsComputed = lib.mapAttrs (name: app: {
  # ... existing port/url/domain fields ...

  build = lib.optionalAttrs (app.build.enable) {
    resolvedLayout = /* computed layout */;
    resolvedSrcRoot = /* computed src root */;
    resolvedLockfile = /* computed lockfile path */;
    hasPackage = app.package != null;
  };
}) computedApps;
```

These computed strings are serializable and reach the UI, letting it show
"auto-detected: workspace" next to the dropdown.

### Flake output summary

After implementation, a project with these apps:

```nix
apps = {
  web = {
    path = "apps/web";
    bun.enable = true;  # implies build.enable = true
  };
  api = {
    path = "apps/api";
    go.enable = true;   # implies build.enable = true
    go.binaryName = "api-server";
  };
  docs = {
    path = "apps/docs";
    # No build - dev-only app
  };
  custom = {
    path = "apps/custom";
    package = myCustomDrv;  # Direct derivation, no build recipe
  };
};
```

Would produce these flake outputs:

```
packages.x86_64-linux.web           # bun2nix.writeBunApplication
packages.x86_64-linux.api           # buildGoApplication (binary: api-server)
packages.x86_64-linux.custom        # user-provided derivation
                                     # (no docs - build not enabled)

checks.x86_64-linux.api-test        # go test ./...

apps.x86_64-linux.web               # nix run .#web
apps.x86_64-linux.api               # nix run .#api
apps.x86_64-linux.custom            # nix run .#custom
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

1. **Phase 1**: Add `build` submodule and `package`/`checkPackage` options
   to the app submodule. Add automatic routing to
   `stackpanel.outputs`/`checks`/`flakeApps`. No breaking changes. Apps
   that don't set `build.enable` are unaffected.

2. **Phase 2**: Add `build` proto schema (`db/schemas/app-build.proto.nix`)
   for UI codegen. Add computed build metadata to `appsComputed`.

3. **Phase 3**: Modify Go module to read `build.*` fields (with fallback
   to current auto-detection) and set `app.package` via `lib.mkDefault`.
   Keep `stackpanel.go.packages` as secondary accessor.

4. **Phase 4**: Modify Bun module similarly.

5. **Phase 5**: Wire `commands.build.package` -> `app.package` connection.

6. **Phase 6** (optional): Add Cargo module. Deprecate
   `stackpanel.go.packages` / `stackpanel.bun.packages`.

## Summary of trade-offs

| Aspect | Alt A (package only) | Alt B (commands) | Alt C (aggregator) | Alt D (structured build) | Recommended (A+D hybrid) |
|---|---|---|---|---|---|
| UI visibility | Poor | Partial | Poor | Excellent | Excellent |
| Source/dep control | Implicit only | Implicit | Implicit | Explicit + auto-detect | Explicit + auto-detect |
| Nix-level simplicity | Excellent | Good | Good | Good | Good |
| Implementation cost | Low | Low | Low | Medium-high | Medium |
| Extensibility | High | Medium | Low | High | High |
| Custom runtime support | Good (set `package`) | Good (set `command`) | Poor | Good (set `build.*` + `package`) | Good (both paths) |
| Backwards compat | Full | Full | Full | Full | Full |
| New module author cost | Low (set `package`) | Low (set `commands`) | Low + update aggregator | Medium (read `build.*`) | Medium (read `build.*`, set `package`) |

## Open Questions

1. **Should `build.enable` auto-activate when `type` is set?** E.g.,
   `type = "bun"` implies `bun.enable = true` implies `build.enable = true`.
   Recommendation: yes for `<runtime>.enable → build.enable`, but NOT for
   `type → <runtime>.enable` (too implicit; `type` is informational, not
   prescriptive).

2. **Should we auto-detect `src.layout` at eval time or defer to the module?**
   At eval time means `builtins.pathExists` in the option default, which
   works but adds eval-time filesystem access. In the module means the
   auto-detection is hidden from the UI (it can't show what was detected).
   Recommendation: detect in the module, expose via `appsComputed.build.resolvedLayout`.

3. **Should `nix run .#<name>` run the built artifact?**
   Recommendation: yes, production mode. Dev mode is process-compose.

4. **Should `build.src.include` use Nix path filtering or a custom mechanism?**
   Recommendation: use `lib.fileset` (modern Nix) or `lib.cleanSourceWith`
   (legacy). The `include` list maps to fileset unions. This is Nix-only
   computation -- the UI just shows/edits the glob list.

5. **Should we expose `packages.default` combining all app packages?**
   Recommendation: yes, `pkgs.symlinkJoin` of all app packages. Useful for CI.

6. **What about the `tooling` options on apps?** The existing `tooling.build`,
   `tooling.install`, etc. overlap with `build` and `commands`. Recommendation:
   keep `tooling` for wrapping external tools (formatters, linters). The `build`
   submodule is for the Nix derivation. They serve different purposes:
   `tooling.build` wraps a shell command for devshell use; `build` produces a
   hermetic Nix package.
