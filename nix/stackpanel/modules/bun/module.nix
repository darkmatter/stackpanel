# ==============================================================================
# module.nix - Bun Module Implementation
#
# Provides Bun/TypeScript application support using bun2nix for hermetic Nix
# packaging and devshell tooling.
#
# Features:
#   - bun2nix CLI in devshell  (converts bun.lock → bun.nix for Nix builds)
#   - Generated package.json   (opt-in via generateFiles; uses json-ops so
#                                existing user content is never stomped)
#   - Hermetic app packaging   (bun2nix.hook pre-populates node_modules from
#                                the Nix store; no network during nix build)
#   - run-<app> / test-<app>   devshell scripts for common workflows
#   - Health checks            bun version, bun2nix availability, bun.nix presence
#
# Two source layouts are supported:
#
#   Per-app:   apps/<name>/bun.nix exists → src = apps/<name>/, build in "."
#   Workspace: only root bun.nix exists   → src = repo root,  build in app subdir
#
# Generated package.json entries use type="json-ops" (applied by preflight) so
# that unrelated user-owned fields are preserved across regeneration.
#
# ⚠ IMPORTANT — do NOT add mkBunPackage results to stackpanel.outputs.
#   fetchBunDeps imports bun.nix which may contain thousands of fetchurl calls.
#   flake-utils.lib.eachSystem forces all per-system outputs (including packages)
#   even during `nix develop`, which would instantiate every FOD derivation for
#   each of the four supported systems and cause nix develop to hang.
#   Built packages are accessible via config.stackpanel.bun.packages.apps.<name>.
#
# App definition example:
#   stackpanel.apps.my-app = {
#     path = "apps/web";
#     bun = {
#       enable = true;
#       buildPhase = "bun run build";
#       startScript = "node .output/server/index.mjs";
#       generateFiles = true;  # writes package.json on shell entry
#     };
#   };
#
# See: https://nix-community.github.io/bun2nix/building-packages/hook.html
# ==============================================================================
{
  lib,
  config,
  pkgs,
  ...
}: let
  meta = import ./meta.nix;
  sp = config.stackpanel;

  # Per-app field definitions are generated from schema.nix (the single source of
  # truth for Bun config). spField.asOption converts each SpField descriptor into
  # a lib.mkOption — keeping the Nix options in sync with proto/Go/TS types.
  bunSchema = import ./schema.nix {inherit lib;};
  spField = import ../../db/lib/field.nix {inherit lib;};

  # NPM scope prefix for workspace dependencies (e.g. "stackpanel" → "@stackpanel").
  # Falls back to project name when project.repo is not set.
  prefix = sp.project.repo or sp.name;

  # Portless integration: when enabled, the dev script routes traffic through the
  # portless reverse proxy instead of listening on a fixed port.
  portlessCfg = config.stackpanel.portless or {enable = false;};
  portsLib = import ../../lib/ports.nix {inherit lib;};
  # Used as the hash seed for stablePort — must be stable across machines.
  repoKey = sp.apps.github or "darkmatter/stackpanel";

  # ---------------------------------------------------------------------------
  # App filtering
  # ---------------------------------------------------------------------------

  # Only apps that opt in via `bun.enable = true` participate in this module.
  bunApps = lib.filterAttrs (_: app: app.bun.enable or false) sp.apps;
  hasBunApps = bunApps != {};

  # ---------------------------------------------------------------------------
  # mkBunPackage — hermetic Nix derivation for a single Bun app
  # ---------------------------------------------------------------------------
  # Build pipeline:
  #   1. bun2nix.hook (nativeBuildInput) copies pre-fetched node_modules from
  #      bunDeps (a fixed-output derivation) into the sandbox — no network needed.
  #   2. postPatch strips lifecycle scripts from all workspace package.json files
  #      so that `bun install` doesn't try to run network-dependent postinstalls.
  #   3. buildPhase runs the app's configured build command.
  #   4. installPhase copies only the build artifact ($outputDir) into $out and
  #      writes a thin bash wrapper at $out/bin/<name> that sets PATH/env and
  #      delegates to startScript.
  #
  # ⚠ fetchBunDeps eagerly instantiates every package listed in bun.nix as a
  #   separate FOD. For large lockfiles (thousands of packages) this writes many
  #   .drv files and is EXPENSIVE at eval time. Never call mkBunPackage from a
  #   path that is forced during `nix develop` (e.g. stackpanel.outputs).
  mkBunPackage = name: app: let
    bunCfg = app.bun;
    appPath = app.path;
    binaryName = if bunCfg.binaryName != null then bunCfg.binaryName else name;

    # repoRoot resolves to the flake's store path at eval time (not the working
    # directory). In a Nix flake, relative paths in .nix files are anchored to
    # the file's location in the store copy of the source tree.
    repoRoot = ../../../..;

    # ---------------------------------------------------------------------------
    # Layout selection: per-app vs. workspace
    # ---------------------------------------------------------------------------
    # Per-app:   apps/<name>/bun.nix present
    #            src = app directory; bun.lock covers only that app's deps;
    #            buildRoot = "."; artifact is at outputDir within the app.
    # Workspace: root bun.nix only
    #            src = entire repo root; bun.lock is the monorepo-level lockfile;
    #            buildRoot = appPath; artifact is at appPath/outputDir.
    hasPerAppBunNix = builtins.pathExists (repoRoot + "/${appPath}/bun.nix");
    layout =
      if hasPerAppBunNix
      then {
        src = repoRoot + "/${appPath}";
        bunNixPath = repoRoot + "/${appPath}/bun.nix";
        buildRoot = ".";
        artifactSourcePath = bunCfg.outputDir;
      }
      else {
        src = repoRoot;
        bunNixPath = repoRoot + "/bun.nix";
        buildRoot = appPath;
        artifactSourcePath = "${appPath}/${bunCfg.outputDir}";
      };

    # Runtime PATH for the generated wrapper script.
    # nodejs is always included so `node` is available when startScript uses it.
    runtimePath = lib.makeBinPath ([pkgs.nodejs] ++ bunCfg.runtimeInputs);

    # Shell fragment that exports any statically-declared runtime env vars.
    # Interpolated directly into the wrapper heredoc by Nix.
    runtimeEnvExports = lib.concatStringsSep "\n" (
      lib.mapAttrsToList
        (key: value: "export ${key}=${lib.escapeShellArg value}")
        bunCfg.runtimeEnv
    );

    # Whether the wrapper script prepends or replaces PATH.
    pathExport =
      if bunCfg.inheritPath
      then ''export PATH="${runtimePath}:$PATH"''
      else ''export PATH="${runtimePath}"'';

    # bun install flags for the Nix sandbox:
    #   --isolated   each package gets its own node_modules (avoids hoisting bugs)
    #   --offline    no network (bun2nix.hook has already populated the cache)
    #   --frozen-lockfile  fail if bun.lock would change (reproducibility guard)
    # On macOS --backend=symlink is required because the default hardlink backend
    # is not supported across the APFS volume boundary used by Nix sandboxing.
    bunInstallFlags =
      if pkgs.stdenv.hostPlatform.isDarwin
      then ["--linker=isolated" "--backend=symlink" "--frozen-lockfile" "--offline"]
      else ["--linker=isolated" "--frozen-lockfile" "--offline"];
  in
    pkgs.stdenv.mkDerivation {
      pname = binaryName;
      version = bunCfg.version;
      src = layout.src;

      # bun2nix.hook sets up the node_modules cache from bunDeps before the
      # build starts. jq is used in postPatch; makeWrapper wraps the output.
      nativeBuildInputs = [
        pkgs.bun2nix.hook
        pkgs.jq
        pkgs.makeWrapper
      ];

      # Pre-fetched dependency cache. fetchBunDeps reads bun.nix and creates a
      # symlink farm of all packages in the Nix store — no downloads at build time.
      bunDeps = pkgs.bun2nix.fetchBunDeps {bunNix = layout.bunNixPath;};
      inherit bunInstallFlags;

      # Skip lifecycle scripts (preinstall/postinstall/prepare) that the Nix
      # sandbox can't execute — they often require network or platform tools.
      dontRunLifecycleScripts = true;

      # Strip lifecycle scripts from every workspace package.json so that bun
      # install doesn't attempt to run them when populating node_modules.
      # This must happen before the bun2nix.hook install phase.
      postPatch = ''
        for manifest in \
            apps/*/package.json \
            packages/*/package.json \
            packages/ui/*/package.json \
            packages/gen/*/package.json; do
          [[ -f "$manifest" ]] || continue
          tmp="$(mktemp)"
          ${lib.getExe pkgs.jq} '
            if .scripts? then
              .scripts |= with_entries(
                select(
                  .key != "preinstall"
                  and .key != "install"
                  and .key != "postinstall"
                  and .key != "prepare"
                )
              )
            else . end
          ' "$manifest" > "$tmp"
          mv "$tmp" "$manifest"
        done
      '';

      buildPhase = ''
        runHook preBuild
        # Run the build command in a subshell so `cd` doesn't affect later phases.
        (
          cd ${lib.escapeShellArg layout.buildRoot}
          ${bunCfg.buildPhase}
        )
        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall

        if [[ ! -d ${lib.escapeShellArg layout.artifactSourcePath} ]]; then
          echo "Expected build artifact directory not found: ${layout.artifactSourcePath}" >&2
          exit 1
        fi

        # Copy only the build artifact — not the full source tree.
        mkdir -p "$out/bin" "$out/${bunCfg.outputDir}"
        cp -R ${lib.escapeShellArg layout.artifactSourcePath}/. "$out/${bunCfg.outputDir}/"

        # Write a thin launcher that sets up the runtime environment and delegates
        # to startScript. Using a heredoc keeps the Nix string escaping clean;
        # ''${...} here is Nix interpolation (resolved at eval time, not at runtime).
        cat > "$out/bin/${binaryName}" <<'WRAPPER'
        #!/usr/bin/env bash
        set -euo pipefail
        ${runtimeEnvExports}
        ${pathExport}
        cd "$out"
        exec ${bunCfg.startScript} "$@"
        WRAPPER
        chmod +x "$out/bin/${binaryName}"

        runHook postInstall
      '';
    };

  # ---------------------------------------------------------------------------
  # generatePackageJson — package.json content for a Bun app
  # ---------------------------------------------------------------------------
  # This attrset is later converted to json-ops by flattenJsonSetOps, so it
  # patches the app's package.json rather than replacing it wholesale.
  generatePackageJson = name: app: let
    bunCfg = app.bun;
    # When portless is active and the app has a domain, wrap the dev command in
    # the portless proxy so that HTTPS termination happens automatically.
    usePortless = portlessCfg.enable && (app.domain or null) != null;
    appPort = portsLib.stablePort {repo = repoKey; service = name;};
    portlessName = "${app.domain}.${portlessCfg.project-name or sp.ports.project-name or "default"}";
    devScript =
      if usePortless
      then "portless ${portlessName} --app-port ${toString appPort} bun run --hot ${bunCfg.mainPackage}"
      else "bun run --hot ${bunCfg.mainPackage}";
  in {
    name = name;
    private = true;
    dependencies = {
      # Pulls in the @<scope>/scripts workspace package which provides
      # `check-devshell` (run in preinstall) and other shared helpers.
      "@${prefix}/scripts" = "workspace:*";
    };
    scripts = {
      # Ensures `bun install` is only run from inside the devshell.
      preinstall = "check-devshell";
      # Regenerates bun.nix after bun.lock changes so Nix builds stay in sync.
      postinstall = "bun2nix";
      dev = devScript;
      build = bunCfg.buildPhase;
      start = bunCfg.startScript;
      test = "bun test";
    };
  };

  # ---------------------------------------------------------------------------
  # flattenJsonSetOps — convert a nested attrset into a list of json-ops
  # ---------------------------------------------------------------------------
  # Recursively walks `value`. When it reaches a leaf (non-attrset), it emits
  # a { op = "set"; path = [...segments]; value = leaf; } operation.
  #
  # Example:
  #   flattenJsonSetOps [] { scripts.dev = "bun run dev"; private = true; }
  #   →  [
  #        { op="set"; path=["scripts" "dev"]; value="bun run dev"; }
  #        { op="set"; path=["private"];       value=true; }
  #      ]
  #
  # This lets Stackpanel's preflight engine surgically patch individual JSON
  # keys rather than replacing the whole file, so user-added fields survive.
  flattenJsonSetOps =
    pathPrefix: value:
    if builtins.isAttrs value
    then
      lib.flatten (
        lib.mapAttrsToList
          (key: nested: flattenJsonSetOps (pathPrefix ++ [key]) nested)
          value
      )
    else [{op = "set"; path = pathPrefix; inherit value;}];

  # ---------------------------------------------------------------------------
  # mkGeneratedFileEntries — stackpanel.files entry for a single app
  # ---------------------------------------------------------------------------
  mkGeneratedFileEntries = name: app: {
    "${app.path}/package.json" = {
      # json-ops patches the file in-place during preflight; the full file is
      # never replaced, so user-added keys (e.g. "engines", "license") survive.
      type = "json-ops";
      # On first adoption, back up the existing file to package.json.backup so
      # users can recover any content that doesn't map to a managed key.
      adopt = "backup";
      ops = flattenJsonSetOps [] (generatePackageJson name app);
      source = "bun";
      description = "Bun app package.json (scripts, dependencies, bun2nix postinstall)";
    };
  };
in {
  # ===========================================================================
  # Options
  # ===========================================================================

  # Read-only store for built Bun application derivations.
  # Type is `unspecified` (not `attrsOf package`) intentionally: using
  # `lib.types.package` would force the NixOS module system to call
  # lib.isDerivation on every value, which instantiates fetchBunDeps and
  # writes thousands of .drv files even during `nix develop`. unspecified
  # sidesteps that type-check without sacrificing correctness.
  options.stackpanel.bun.packages = lib.mkOption {
    type = lib.types.attrsOf lib.types.unspecified;
    default = {};
    description = ''
      Built Bun application derivations, keyed by app name.
      Populated as { apps.<name> = <derivation>; } for each app with bun.enable = true.

      NOT added to stackpanel.outputs (see the ⚠ note at the top of this file).
      To build: nix build via config.stackpanel.bun.packages.apps.<name>
    '';
  };

  # ===========================================================================
  # Configuration
  # ===========================================================================
  config = lib.mkMerge [
    # -------------------------------------------------------------------------
    # Always-on: register the per-app `bun.*` option set.
    # -------------------------------------------------------------------------
    # This block is unconditional so that every app always has a valid
    # `app.bun` submodule regardless of whether any app has bun.enable = true.
    # The options themselves come from schema.nix (proto-derived SpFields) which
    # is the single source of truth shared with Go/TS codegen. Only runtimeInputs
    # is added manually because package references have no proto equivalent.
    {
      stackpanel.appModules = [
        ({lib, ...}: {
          options.bun = lib.mkOption {
            type = lib.types.submodule {
              options =
                # Auto-generated from schema.nix SpField descriptors.
                lib.mapAttrs (_: spField.asOption) bunSchema.fields
                // {
                  # Nix-only: package references cannot be represented in proto.
                  runtimeInputs = lib.mkOption {
                    type = lib.types.listOf lib.types.package;
                    default = [];
                    description = "Additional Nix packages to add to the runtime PATH of the generated wrapper.";
                  };
                };
            };
            default = {};
            description = "Bun-specific configuration for this app. See schema.nix for field definitions.";
          };
        })
      ];
    }

    # -------------------------------------------------------------------------
    # Conditional: activate devshell tooling only when bun apps are defined.
    # -------------------------------------------------------------------------
    # Guarded by hasBunApps so that the module contributes nothing to projects
    # that don't use Bun — zero overhead for unrelated stackpanel users.
    (lib.mkIf (sp.enable && hasBunApps) {
      # -----------------------------------------------------------------------
      # Packages
      # -----------------------------------------------------------------------
      # Built lazily; see ⚠ note at top of file for why these must NOT be
      # copied into stackpanel.outputs.
      stackpanel.bun.packages = {
        apps = lib.mapAttrs mkBunPackage bunApps;
      };

      # -----------------------------------------------------------------------
      # Devshell
      # -----------------------------------------------------------------------
      # bun2nix CLI: run `bun2nix` after `bun install` to regenerate bun.nix
      # whenever bun.lock changes.  The postinstall script in the generated
      # package.json invokes this automatically.
      stackpanel.devshell.packages = [
        pkgs.bun # Bun runtime
        pkgs.bun2nix # Native bun2nix CLI (converts bun.lock -> bun.nix)
      ];

      # -----------------------------------------------------------------------
      # File Generation — package.json
      # -----------------------------------------------------------------------
      # Only generated for apps with generateFiles = true (default). Each entry
      # uses json-ops so the file is patched in-place; user-added fields are
      # never overwritten. Materialized by `stackpanel preflight run` on shell entry.
      stackpanel.files.entries = lib.mkMerge (
        lib.mapAttrsToList
          (name: app: lib.optionalAttrs app.bun.generateFiles (mkGeneratedFileEntries name app))
          bunApps
      );

      # -----------------------------------------------------------------------
      # Devshell Scripts
      # -----------------------------------------------------------------------
      stackpanel.scripts = lib.mkMerge (
        lib.mapAttrsToList (name: app: {
          "run-${name}" = {
            exec = ''cd "$STACKPANEL_ROOT/${app.path}" && exec bun run ${app.bun.mainPackage} "$@"'';
            runtimeInputs = [pkgs.bun];
            description = "Run ${name} Bun app";
            args = [{name = "..."; description = "Arguments passed to the bun script";}];
          };
          "test-${name}" = {
            exec = ''cd "$STACKPANEL_ROOT/${app.path}" && exec bun test "$@"'';
            runtimeInputs = [pkgs.bun];
            description = "Test ${name} Bun app";
            args = [{name = "..."; description = "Arguments passed to bun test";}];
          };
        })
        bunApps
      );

      # -----------------------------------------------------------------------
      # Flake Checks (CI)
      # -----------------------------------------------------------------------
      stackpanel.moduleChecks.${meta.id} = {
        eval = {
          description = "${meta.name} module evaluates correctly";
          required = true;
          derivation = pkgs.runCommand "${meta.id}-eval-check" {} ''
            echo "Bun module evaluates successfully"
            touch $out
          '';
        };
        packages = {
          description = "Bun runtime is present in the Nix store";
          required = true;
          derivation = pkgs.runCommand "${meta.id}-packages-check" {nativeBuildInputs = [pkgs.bun];} ''
            bun --version
            touch $out
          '';
        };
      };

      # -----------------------------------------------------------------------
      # Health Checks (runtime, run by `sp healthcheck`)
      # -----------------------------------------------------------------------
      stackpanel.healthchecks.modules.${meta.id} = {
        enable = true;
        displayName = meta.name;
        checks = {
          bun-installed = {
            description = "Bun runtime is installed and accessible";
            script = ''
              command -v bun >/dev/null 2>&1 && bun --version
            '';
            severity = "critical";
            timeout = 5;
          };

          bun-version = {
            description = "Bun version is 1.2 or newer";
            script = ''
              version=$(bun --version 2>/dev/null)
              major=$(echo "$version" | cut -d. -f1)
              minor=$(echo "$version" | cut -d. -f2)
              [ "$major" -gt 1 ] || { [ "$major" -eq 1 ] && [ "$minor" -ge 2 ]; }
            '';
            severity = "warning";
            timeout = 5;
          };

          bun2nix-installed = {
            description = "bun2nix CLI is installed and accessible";
            script = ''
              command -v bun2nix >/dev/null 2>&1 && bun2nix --version
            '';
            severity = "warning";
            timeout = 5;
          };

          lockfile-exists = {
            description = "bun.nix lockfile exists for Nix builds";
            script = ''
              STACKPANEL_ROOT="''${STACKPANEL_ROOT:-$(pwd)}"
              test -f "$STACKPANEL_ROOT/bun.nix" || \
              find "$STACKPANEL_ROOT/apps" -name "bun.nix" -type f | head -1 | grep -q .
            '';
            severity = "warning";
            timeout = 5;
          };
        };
      };

      # -----------------------------------------------------------------------
      # Module Registration
      # -----------------------------------------------------------------------
      stackpanel.modules.${meta.id} = {
        enable = true;
        meta = {
          name = meta.name;
          description = meta.description;
          icon = meta.icon;
          category = meta.category;
          author = meta.author;
          version = meta.version;
          homepage = meta.homepage;
        };
        source.type = "builtin";
        features = meta.features;
        flakeInputs = meta.flakeInputs or [];
        tags = meta.tags;
        priority = meta.priority;
        healthcheckModule = meta.id;
      };
    })
  ];
}
