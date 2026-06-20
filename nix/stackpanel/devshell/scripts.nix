# ==============================================================================
# scripts.nix
#
# Unified script management for stackpanel devshells.
#
# This module consolidates script/command definitions into a single
# `stackpanel.scripts` option. All scripts are bundled into a single package
# with executables in `bin/`, avoiding conflicts and providing clean namespace.
#
# Schema defined in: nix/stackpanel/db/schemas/scripts.proto.nix
#
# Features:
#   - Attribute set keyed by command name (ensures no conflicts)
#   - Single package with all scripts in `bin/`
#   - Optional devshell integration (enabled by default)
#   - Support for runtimeInputs, env, and description
#   - Load script content from files via `path` option
#
# Usage (inline exec):
#   stackpanel.scripts.db-seed = {
#     exec = "npm run seed";
#     description = "Seed the database with test data";
#   };
#
# Usage (path to file):
#   stackpanel.scripts.db-seed = {
#     path = ./.stack/src/scripts/db-seed.sh;
#     description = "Seed the database with test data";
#     runtimeInputs = [ pkgs.nodejs ];
#   };
#
# Extension scripts use namespace prefix:
#   stackpanel.scripts."sst:deploy" = {
#     path = ./src/scripts/deploy.sh;
#     description = "Deploy SST infrastructure";
#   };
# ==============================================================================
{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Import proto-derived options from db
  db = import ../db { inherit lib; };

  cfg = config.stackpanel.scripts;
  scriptsCfg = config.stackpanel.scriptsConfig;

  # Timeout presets for common script types
  # These provide sensible defaults for different use cases
  timeouts = {
    quick = 30; # 30 seconds - quick checks, simple commands
    default = 300; # 5 minutes - most scripts (network calls, builds)
    build = 900; # 15 minutes - complex builds, compilations
    deploy = 1800; # 30 minutes - deployments, migrations
    long = 3600; # 1 hour - long-running data processing
    none = 0; # No timeout - use with caution
  };

  # Resolve script content from either exec or path
  resolveScriptContent =
    name: script:
    let
      hasExec = script.exec or null != null && script.exec != "";
      hasPath = script.path or null != null;
    in
    if hasExec && hasPath then
      throw "Script '${name}': cannot specify both 'exec' and 'path' - use one or the other"
    else if hasPath then
      builtins.readFile script.path
    else if hasExec then
      script.exec
    else
      throw "Script '${name}': must specify either 'exec' or 'path'";

  # Build a single script executable
  mkScript =
    name: script:
    let
      envExports = lib.concatStringsSep "\n" (
        lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg v}") (script.env or { })
      );
      scriptContent = resolveScriptContent name script;

      # Timeout configuration (default: 300 seconds = 5 minutes)
      # Set to 0 to disable timeout
      # Common presets available: timeouts.quick (30s), timeouts.build (15m), etc.
      timeoutSeconds = script.timeout or timeouts.default;
      hasTimeout = timeoutSeconds > 0;

      # Wrap script with timeout if configured
      # The timeout command from coreutils will SIGTERM after the specified duration
      # and SIGKILL after an additional 10 seconds if the process doesn't terminate
      wrappedContent =
        if hasTimeout then
          ''
            # Script timeout: ${toString timeoutSeconds} seconds (${toString (timeoutSeconds / 60.0)} minutes)
            # This prevents the script from hanging indefinitely on network issues, waiting for input, etc.
            # Note: We use a temp file instead of a heredoc (bash -s <<EOF) because heredocs
            # consume stdin, which causes commands like `nix build` to receive EOF on stdin
            # and exit with "error: interrupted by user".
            _sp_script_tmp=$(mktemp)
            trap 'rm -f "$_sp_script_tmp"' EXIT
            cat > "$_sp_script_tmp" <<'SCRIPT_TIMEOUT_EOF'
            set -euo pipefail
            ${scriptContent}
            SCRIPT_TIMEOUT_EOF
            timeout ${toString timeoutSeconds} bash "$_sp_script_tmp" "$@"
          ''
        else
          scriptContent;
    in
    pkgs.writeShellApplication {
      inherit name;
      # Always include coreutils for timeout command support
      runtimeInputs = (script.runtimeInputs or [ ]) ++ [ pkgs.coreutils ];
      text = ''
        set -euo pipefail
        ${envExports}
        ${wrappedContent}
      '';
    };

  # Build all scripts as individual packages
  scriptPackages = lib.mapAttrs mkScript cfg;

  # Create a combined package with bin/ directory containing all scripts
  scriptsPackage = pkgs.symlinkJoin {
    name = "stackpanel-scripts";
    paths = lib.attrValues scriptPackages;
    meta = {
      description = "Stackpanel project scripts";
    };
  };

  # Generate serializable script definitions for CLI/agent access
  # Uses derivation paths instead of inline content for security
  serializableScripts = lib.mapAttrs (
    name: script:
    let
      pkg = scriptPackages.${name};
    in
    {
      inherit name;
      description = script.description or null;
      env = script.env or { };
      # Documented arguments for help text
      args = script.args or [ ];
      # Timeout in seconds (0 = no timeout, default: 300)
      timeout = script.timeout or timeouts.default;
      # Derivation path - agent executes this directly (no sh -c with inline content)
      binPath = "${pkg}/bin/${name}";
      # Source info for debugging
      source = if script.path or null != null then "path" else "inline";
    }
  ) cfg;

  hasScripts = builtins.length (builtins.attrNames cfg) > 0;

  # Generate package.json scripts map for optional Turbo workspace package
  generatedPackageScripts = lib.mapAttrs (_name: _scriptCfg: _name) cfg;

  # Collect scripts that declare turbo metadata
  turboEnabledScripts = lib.filterAttrs (_name: script: (script.turbo.enable or false)) cfg;

  # Build stackpanel.tasks entries from per-script turbo metadata
  generatedTurboTasks = lib.mapAttrs (
    _scriptName: scriptCfg:
    { }
    // lib.optionalAttrs ((scriptCfg.turbo.dependsOn or [ ]) != [ ]) {
      inherit (scriptCfg.turbo) dependsOn;
    }
    // lib.optionalAttrs ((scriptCfg.turbo.outputs or [ ]) != [ ]) {
      inherit (scriptCfg.turbo) outputs;
    }
    // lib.optionalAttrs ((scriptCfg.turbo.inputs or [ ]) != [ ]) {
      inherit (scriptCfg.turbo) inputs;
    }
    // lib.optionalAttrs ((scriptCfg.turbo.cache or null) != null) {
      inherit (scriptCfg.turbo) cache;
    }
    // lib.optionalAttrs ((scriptCfg.turbo.persistent or null) != null) {
      inherit (scriptCfg.turbo) persistent;
    }
    // lib.optionalAttrs ((scriptCfg.turbo.interactive or null) != null) {
      inherit (scriptCfg.turbo) interactive;
    }
  ) turboEnabledScripts;

  # Nix-only script options (not serializable to proto - contains packages/paths)
  nixScriptOptionsModule =
    { lib, ... }:
    {
      options = {
        # Path is Nix-only because it uses types.path (not serializable as string)
        path = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = ''
            Path to script file. Content is read and used as the script body.
            Mutually exclusive with `exec` - use one or the other.
          '';
          example = lib.literalExpression "./.stack/src/scripts/my-script.sh";
        };

        runtimeInputs = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [ ];
          description = ''
            Packages to include in PATH when running the script.
            These are pinned to specific Nix store paths, ensuring reproducible execution.
          '';
          example = lib.literalExpression "[ pkgs.nodejs pkgs.jq ]";
        };

        turbo = lib.mkOption {
          type = lib.types.submodule {
            options = {
              enable = lib.mkOption {
                type = lib.types.bool;
                default = false;
                description = ''
                  Register this script as a Turborepo task.

                  When enabled and scriptsConfig.generateTurboPackage is true,
                  Stackpanel emits matching stackpanel.tasks metadata so turbo.json
                  can reference this command with cache settings and dependencies.
                '';
                example = true;
              };

              dependsOn = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = ''
                  Turborepo task dependencies for this script.
                  Example: [ "^build" "lint" ].
                '';
                example = [
                  "^build"
                  "lint"
                ];
              };

              outputs = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = ''
                  Turborepo output globs produced by this script.

                  Set for build/codegen scripts whose artifacts should be cached.
                  Leave empty for checks that do not write durable outputs.
                '';
                example = [
                  "dist/**"
                  ".stack/gen/**"
                ];
              };

              inputs = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
                description = ''
                  Turborepo input globs used to compute this script's cache key.

                  Use when defaults are too broad or too narrow, such as scripts
                  that depend on Nix config, proto files, or generator sources.
                '';
                example = [
                  "nix/**/*.nix"
                  "packages/proto/**/*.proto"
                ];
              };

              cache = lib.mkOption {
                type = lib.types.nullOr lib.types.bool;
                default = null;
                description = ''
                  Override Turborepo cache behavior for this script.

                  Null leaves Turbo defaults intact. Set false for tasks with
                  side effects such as deploys, migrations, or service control.
                '';
                example = false;
              };

              persistent = lib.mkOption {
                type = lib.types.nullOr lib.types.bool;
                default = null;
                description = ''
                  Mark this Turborepo task as a long-running process.

                  Use for dev servers and watchers that should stay alive instead
                  of producing a finite cached result.
                '';
                example = true;
              };

              interactive = lib.mkOption {
                type = lib.types.nullOr lib.types.bool;
                default = null;
                description = ''
                  Mark this Turborepo task as interactive.

                  Use for commands that read stdin or open prompts, such as login
                  flows, CLIs, or local database consoles.
                '';
                example = true;
              };
            };
          };
          default = { };
          description = ''
            Optional Turborepo metadata for this script.
            When turbo.enable = true and scriptsConfig.generateTurboPackage is enabled,
            script metadata is exported to stackpanel.tasks and included in turbo.json.
          '';
          example = {
            enable = true;
            dependsOn = [ "^build" ];
            outputs = [ "dist/**" ];
            cache = true;
          };
        };
      };
    };
in
{
  options.stackpanel.scriptModules = lib.mkOption {
    type = lib.types.listOf lib.types.deferredModule;
    default = [ ];
    description = ''
      Additional modules to extend script configuration options.

      Use sparingly for extension modules that need script-local fields beyond
      the proto schema and Nix-only path/runtimeInputs/turbo options.
    '';
    example = lib.literalExpression ''
      [
        ({ lib, ... }: {
          options.category = lib.mkOption {
            type = lib.types.str;
            default = "local";
          };
        })
      ]
    '';
  };

  options.stackpanel.scripts = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submoduleWith {
        modules = [
          # Proto-derived options (exec, description, env, timeout)
          { options = db.asOptions db.extend.script; }
          # Set timeout default (proto defines the option, we set the default)
          { config.timeout = lib.mkDefault timeouts.default; }
          # Nix-only runtime options (runtimeInputs, path)
          nixScriptOptionsModule
        ]
        ++ config.stackpanel.scriptModules;
        specialArgs = { inherit lib; };
      }
    );
    default = { };
    description = ''
      Scripts exposed in the development shell.

      Each script becomes an executable command available in PATH.
      The attribute name determines the command name.

      Script content can be provided via:
        - exec: Inline shell command
        - path: Path to script file (content is read at eval time)

      These are mutually exclusive - use one or the other.

      Proto-derived options (from scripts.proto.nix):
        - exec: Shell command to execute
        - description: Human-readable description
        - env: Environment variables

      Nix extensions:
        - path: Path to script file (alternative to inline exec)
        - runtimeInputs: Nix packages for PATH

      Extension scripts should use namespace prefix (e.g., "sst:deploy").
    '';
    example = lib.literalExpression ''
      {
        # Inline exec
        db-seed = {
          exec = "npm run seed";
          description = "Seed the database with test data";
        };

        # Path to script file
        deploy = {
          path = ./.stack/src/scripts/deploy.sh;
          description = "Deploy the application";
          runtimeInputs = [ pkgs.awscli2 ];
        };

        # Extension-namespaced script
        "sst:dev" = {
          exec = "sst dev";
          description = "Start SST dev mode";
          runtimeInputs = [ pkgs.nodejs ];
        };
      }
    '';
  };

  options.stackpanel.scriptsConfig = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Add the generated scripts package to stackpanel.devshell.packages.

        When true, each stackpanel.scripts entry is available as a shell command,
        listed in serializable command metadata, and exposed as flake outputs.
      '';
      example = true;
    };

    generateTurboPackage = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to generate a Turbo-managed workspace package for scripts at
        scriptsConfig.turboPackagePath (default: packages/gen/scripts).

        When enabled, this creates/merges package.json scripts via stackpanel.turbo.packages
        and registers script-level turbo metadata (when script.turbo.enable = true)
        into stackpanel.tasks for turbo.json generation.
      '';
      example = true;
    };

    turboPackageId = lib.mkOption {
      type = lib.types.str;
      default = "scripts";
      description = ''
        Identifier key under stackpanel.turbo.packages for generated scripts.

        Change when another package already owns the "scripts" id or when an
        extension needs a namespaced generated package.
      '';
      example = "local-scripts";
    };

    turboPackageName = lib.mkOption {
      type = lib.types.str;
      default = "@gen/scripts";
      description = ''
        NPM package name for the generated scripts workspace package.

        Used in the generated package.json when script commands are mirrored into
        a Turbo-managed workspace package.
      '';
      example = "@gen/stackpanel-scripts";
    };

    turboPackagePath = lib.mkOption {
      type = lib.types.str;
      default = "packages/gen/scripts";
      description = ''
        Workspace-relative path for the generated scripts package.json.

        Keep this under a generated package directory so package-manager and
        Turborepo discovery can include it without mixing with handwritten code.
      '';
      example = "packages/gen/scripts";
    };

    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = scriptsPackage;
      description = ''
        Generated combined scripts package, read-only.

        This symlinkJoin contains one executable per stackpanel.scripts entry and
        is appended to stackpanel.devshell.packages when scriptsConfig.enable is
        true.
      '';
      example = lib.literalExpression ''
        config.stackpanel.scriptsConfig.package
      '';
    };

    packages = lib.mkOption {
      type = lib.types.attrsOf lib.types.package;
      readOnly = true;
      default = scriptPackages;
      description = ''
        Individual script packages (read-only).

        Each value is a derivation containing one generated executable. Use this
        when another module needs to depend on or expose a specific script rather
        than the combined scriptsConfig.package.
      '';
      example = lib.literalExpression ''
        config.stackpanel.scriptsConfig.packages.db-seed
      '';
    };
  };

  config = lib.mkIf (hasScripts && scriptsCfg.enable) (
    lib.mkMerge [
      {
        # Add the scripts package to devshell
        stackpanel.devshell.packages = [ scriptsPackage ];

        # Store serializable definitions for CLI/TUI access
        stackpanel.devshell._commandsSerializable = serializableScripts;

        # Expose individual script packages as flake outputs
        # Available via: nix run .#scripts.<script-name>
        stackpanel.outputs.scripts = scriptPackages;

        # Also expose the combined package
        stackpanel.outputs.stackpanel-scripts = scriptsPackage;

        # Print available scripts on shell entry
        stackpanel.devshell.hooks.main = [
          ''
            echo "📜 stackpanel scripts loaded"
          ''
        ];
      }

      (lib.mkIf scriptsCfg.generateTurboPackage {
        stackpanel.turbo.packages.${scriptsCfg.turboPackageId} = {
          name = scriptsCfg.turboPackageName;
          path = scriptsCfg.turboPackagePath;
          scripts = lib.mapAttrs (_scriptName: command: { exec = command; }) generatedPackageScripts;
        };

        stackpanel.tasks = generatedTurboTasks;
      })
    ]
  );
}
