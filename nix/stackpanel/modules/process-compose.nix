# ==============================================================================
# process-compose.nix
#
# Process-compose integration for stackpanel.
#
# This module:
#   1. Defines stackpanel.process-compose.{enable, processes, environment, package}
#   2. Auto-generates process entries from apps (defaults to turbo run -F <name> dev)
#   3. Creates a `dev` wrapper package added to devshell
#
# Usage:
#   # All apps get a dev process by default using: turbo run -F <name> dev
#   # Just define the app:
#   web = {
#     path = "apps/web";
#   };
#
#   # Override with explicit command if needed:
#   api = {
#     path = "apps/api";
#     tasks.dev.command = "go run ./cmd/api";
#   };
#
#   # Disable process-compose for a specific app:
#   stackpanel.apps.legacy.process-compose.enable = false;
#
# Access the generated config:
#   config.stackpanel.process-compose.processes
#   config.stackpanel.process-compose.package
# ==============================================================================
{
  lib,
  config,
  pkgs,
  options,
  ...
}:
let
  cfg = config.stackpanel;
  pcCfg = cfg.process-compose;

  # Check for devenv compatibility
  hasDevenvProcessesOption = options ? processes;

  # Default command uses turbo with filter flag (full store path for reliability)
  turbo = "${pkgs.turbo}/bin/turbo";
  mkDefaultCommand = name: taskKey: "${turbo} run -F ${name} ${taskKey}";

  # watchexec for file watching
  watchexec = "${pkgs.watchexec}/bin/watchexec";

  # ---------------------------------------------------------------------------
  # Per-app process-compose options (added via appModules)
  # ---------------------------------------------------------------------------
  processComposeAppModule =
    { lib, ... }:
    {
      options.process-compose = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether to include this app in process-compose.";
        };
        name = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Override process name (defaults to app name).";
        };
        namespace = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Process-compose namespace for grouping.";
        };
      };
    };

  # ---------------------------------------------------------------------------
  # Process entry generation (functions only - evaluation happens in config)
  # ---------------------------------------------------------------------------

  # Generate process-compose process entries from an app
  mkProcessEntry =
    name: app:
    let
      pcAppCfg = app.process-compose or { };
      # Use explicit null check since pcAppCfg.name can be null (not missing)
      processName = if pcAppCfg.name or null != null then pcAppCfg.name else name;

      # Get task commands, falling back to turbo defaults
      devTask = app.tasks.dev or { };
      devCommand = devTask.command or (mkDefaultCommand name "dev");
    in
    {
      ${processName} = {
        command = devCommand;
        working_dir = app.path or null;
      }
      // lib.optionalAttrs (pcAppCfg.namespace or null != null) {
        namespace = pcAppCfg.namespace;
      };
    };

  # Generate app process entries - must be called with apps from config
  mkAppProcessEntries = apps:
    let
      appsWithProcessCompose = lib.filterAttrs (name: app: app.process-compose.enable or true) apps;
    in
    lib.foldl' (acc: name: acc // (mkProcessEntry name apps.${name})) { } (
      lib.attrNames appsWithProcessCompose
    );

  # ---------------------------------------------------------------------------
  # Infrastructure processes (format watcher, etc.)
  # ---------------------------------------------------------------------------

  # Build infrastructure processes (format watcher)
  mkInfrastructureProcesses =
    formatWatcherCfg:
    let
      formatExtensions =
        formatWatcherCfg.extensions or [
          "ts"
          "tsx"
          "js"
          "jsx"
          "json"
          "md"
          "css"
          "scss"
          "html"
          "nix"
          "go"
          "rs"
          "py"
        ];
      formatCommand =
        if formatWatcherCfg.command or null != null then
          formatWatcherCfg.command
        else
          "${turbo} run format --continue";
      formatExtStr = lib.concatStringsSep "," formatExtensions;
    in
    lib.optionalAttrs (formatWatcherCfg.enable or true) {
      format-watch = {
        command = "${watchexec} --exts ${formatExtStr} -- ${formatCommand}";
        working_dir = null;
        namespace = "infra";
        availability = {
          restart = "always";
          backoff_seconds = 2;
        };
      };
    };

  # ---------------------------------------------------------------------------
  # Devenv-compatible process entries (uses exec instead of command)
  # ---------------------------------------------------------------------------
  mkDevenvProcessEntry =
    name: app:
    let
      pcAppCfg = app.process-compose or { };
      # Use explicit null check since pcAppCfg.name can be null (not missing)
      processName = if pcAppCfg.name or null != null then pcAppCfg.name else name;

      devTask = app.tasks.dev or { };
      devCommand = devTask.command or (mkDefaultCommand name "dev");
    in
    {
      ${processName} = {
        exec = devCommand;
        process-compose = {
          working_dir = app.path or null;
        };
      };
    };

  # Generate devenv process entries - must be called with apps from config
  mkDevenvAppProcessEntries = apps:
    let
      appsWithProcessCompose = lib.filterAttrs (name: app: app.process-compose.enable or true) apps;
    in
    lib.foldl' (acc: name: acc // (mkDevenvProcessEntry name apps.${name})) { } (
      lib.attrNames appsWithProcessCompose
    );

  # Infrastructure processes for devenv format
  mkInfrastructureDevenvProcesses =
    formatWatcherCfg:
    let
      formatExtensions =
        formatWatcherCfg.extensions or [
          "ts"
          "tsx"
          "js"
          "jsx"
          "json"
          "md"
          "css"
          "scss"
          "html"
          "nix"
          "go"
          "rs"
          "py"
        ];
      formatCommand =
        if formatWatcherCfg.command or null != null then
          formatWatcherCfg.command
        else
          "${turbo} run format --continue";
      formatExtStr = lib.concatStringsSep "," formatExtensions;
    in
    lib.optionalAttrs (formatWatcherCfg.enable or true) {
      format-watch = {
        exec = "${watchexec} --exts ${formatExtStr} -- ${formatCommand}";
        process-compose = {
          namespace = "infra";
          availability = {
            restart = "always";
            backoff_seconds = 2;
          };
        };
      };
    };

  # ---------------------------------------------------------------------------
  # Package generation
  # ---------------------------------------------------------------------------

  # Remove null values recursively for clean JSON
  removeNulls = attrs: lib.filterAttrsRecursive (k: v: v != null && v != { }) attrs;

  # Build the dev wrapper package
  mkDevPackage =
    {
      processes,
      environment,
      commandName,
    }:
    let
      processCount = builtins.length (lib.attrNames processes);
      processNames = lib.attrNames processes;
      # process-compose expects environment as a list of KEY=VALUE strings
      envList = lib.mapAttrsToList (k: v: "${k}=${v}") environment;
      configFile = pkgs.writeText "process-compose.yaml" (
        lib.generators.toYAML { } (removeNulls {
          version = "0.5";
          inherit processes;
          environment = envList;
        })
      );
    in
    pkgs.writeShellApplication {
      name = commandName;
      runtimeInputs = [
        pkgs.process-compose
        pkgs.watchexec
        pkgs.turbo
      ];
      text = ''
        set -euo pipefail

        CONFIG_PATH=${configFile}
        PROCESS_COUNT=${toString processCount}
        STATE_DIR="''${STACKPANEL_STATE_DIR:-$PWD/.stackpanel/state}/process-compose"

        mkdir -p "$STATE_DIR"

        # Force interactive TUI and ignore any devenv-provided configs
        unset PC_NO_TUI PROCESS_COMPOSE_NO_TUI
        export PC_CONFIG_FILES=
        export PC_CONFIG=
        export PROCESS_COMPOSE_FILE=
        export PROCESS_COMPOSE_CONFIG=
        export PC_TUI=1
        export PROCESS_COMPOSE_DIR="$STATE_DIR"

        if [[ "$PROCESS_COUNT" -eq 0 ]]; then
          echo "⚠️  No processes configured for process-compose (config: $CONFIG_PATH)"
          echo "   Define apps or set stackpanel.process-compose.processes."
          exit 1
        fi

        echo "🚀 Starting process-compose with $PROCESS_COUNT process(es) from $CONFIG_PATH"
        echo "    ${lib.concatStringsSep ", " processNames}"
        exec env -u PC_CONFIG_FILES -u PC_CONFIG -u PROCESS_COMPOSE_FILE -u PROCESS_COMPOSE_CONFIG \
          process-compose up -f "$CONFIG_PATH" "$@"
      '';
    };
in
{
  # ===========================================================================
  # Options
  # ===========================================================================
  options.stackpanel.process-compose = {
    enable = lib.mkEnableOption "process-compose integration" // {
      default = true;
    };

    commandName = lib.mkOption {
      type = lib.types.str;
      default = "dev";
      description = ''
        Name of the command to start all processes.
        Change this if it conflicts with a global alias or shell builtin.
      '';
      example = "start";
    };

    formatWatcher = {
      enable = lib.mkEnableOption "format watcher process" // {
        default = true;
      };

      extensions = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "ts"
          "tsx"
          "js"
          "jsx"
          "json"
          "md"
          "css"
          "scss"
          "html"
          "nix"
          "go"
          "rs"
          "py"
        ];
        description = "File extensions to watch for format changes.";
      };

      command = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Custom format command. If null, uses `turbo run format --continue`.
        '';
      };
    };

    processes = lib.mkOption {
      type = lib.types.attrsOf lib.types.unspecified;
      default = { };
      description = ''
        Process definitions for process-compose.

        This is auto-populated from apps. Each app gets a process using
        `turbo run -F <name> dev` by default, or the explicit command from
        `tasks.dev.command` if defined.
      '';
      example = lib.literalExpression ''
        {
          web = {
            command = "turbo run -F web dev";
            working_dir = "apps/web";
          };
          api = {
            command = "go run ./cmd/api";
            working_dir = "apps/api";
          };
        }
      '';
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = ''
        Environment variables for process-compose.

        These are passed to all processes.
      '';
      example = lib.literalExpression ''
        {
          STACKPANEL_PORTS = builtins.toJSON config.stackpanel.ports;
          NODE_ENV = "development";
        }
      '';
    };

    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      description = ''
        The process-compose wrapper package.

        This is a script (named by `commandName`, default "dev") that runs
        `process-compose up` with the generated configuration.
        Added to devshell automatically.
      '';
    };
  };

  # ===========================================================================
  # Config
  # ===========================================================================
  config = lib.mkMerge [
    # Add the per-app process-compose options to all apps
    {
      stackpanel.appModules = [ processComposeAppModule ];
    }

    # When stackpanel is enabled, populate process-compose from apps
    (lib.mkIf cfg.enable {
      # Populate process-compose.processes from apps (evaluated with cfg.apps available)
      stackpanel.process-compose.processes =
        let
          appProcesses = mkAppProcessEntries cfg.apps;
          infraProcesses = mkInfrastructureProcesses pcCfg.formatWatcher;
        in
        appProcesses // infraProcesses;

      # Default environment with ports
      stackpanel.process-compose.environment = {
        STACKPANEL_PORTS = builtins.toJSON (cfg.ports or { });
      };
    })

    # When process-compose is enabled, build the wrapper package and add to devshell
    (lib.mkIf (cfg.enable && pcCfg.enable) {
      # Ensure devshell environment does not inherit devenv process-compose vars
      # Use mkOverride 50 (higher priority than mkForce which is 100) to override
      # devenv's process-compose module settings
      stackpanel.devshell.env = {
        PC_CONFIG_FILES = lib.mkOverride 50 "";
        PC_CONFIG = lib.mkOverride 50 "";
        PROCESS_COMPOSE_FILE = lib.mkOverride 50 "";
        PROCESS_COMPOSE_CONFIG = lib.mkOverride 50 "";
        PROCESS_COMPOSE_DIR = lib.mkOverride 50 "";
        PC_NO_TUI = lib.mkOverride 50 "";
        PROCESS_COMPOSE_NO_TUI = lib.mkOverride 50 "";
      };

      stackpanel.process-compose.package = mkDevPackage {
        commandName = pcCfg.commandName;
        processes = pcCfg.processes;
        environment = pcCfg.environment;
      };

      # Add both process-compose CLI and our wrapper to devshell
      stackpanel.devshell.packages = [
        pkgs.process-compose
        pcCfg.package
      ];

      # Auto-clean the command alias to avoid conflicts with user's shell aliases
      stackpanel.devshell.clean.aliases = [ pcCfg.commandName ];
    })

    # Devenv compatibility: if `processes` option exists at top level, populate it
    (lib.optionalAttrs hasDevenvProcessesOption (
      lib.mkIf (cfg.enable && pcCfg.enable) {
        processes =
          let
            appProcesses = mkDevenvAppProcessEntries cfg.apps;
            infraProcesses = mkInfrastructureDevenvProcesses pcCfg.formatWatcher;
          in
          appProcesses // infraProcesses;
      }
    ))
  ];
}
