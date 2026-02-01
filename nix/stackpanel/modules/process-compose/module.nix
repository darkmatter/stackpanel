# ==============================================================================
# module.nix - Process Compose Module Implementation
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
  meta = import ./meta.nix;
  cfg = config.stackpanel;
  pcCfg = cfg.process-compose;

  # Check for devenv compatibility
  hasDevenvProcessesOption = options ? processes;

  # Default command uses turbo with filter flag (full store path for reliability)
  turbo = "${pkgs.turbo}/bin/turbo";
  jq = "${pkgs.jq}/bin/jq";

  # Entrypoint scripts directory (relative to repo root)
  entrypointsDir = "packages/scripts/entrypoints";

  # Generate command that sources entrypoint (if available) then runs the actual command
  # Entrypoints ONLY set up environment (secrets, devshell). They do NOT run commands.
  mkDefaultCommand = name: app: taskKey:
    let
      appPath = app.path or name;
      entrypointScript = "${entrypointsDir}/${name}.sh";
      # If packageName is explicitly set, use it; otherwise read from package.json at runtime
      filterExpr =
        if app.packageName or null != null then
          "\"${app.packageName}\""
        else
          "$(${jq} -r .name ${appPath}/package.json 2>/dev/null || echo '${name}')";
      directCommand = "${turbo} run -F ${filterExpr} ${taskKey}";
      # Source entrypoint to set up environment, then run the command
      # The entrypoint exports env vars; we then exec the actual command
      commandWithEntrypoint = "source ${entrypointScript} --dev && exec ${directCommand}";
    in
    # Source entrypoint if it exists (for env setup), then run the command
    "if [[ -f ${entrypointScript} ]]; then ${commandWithEntrypoint}; else exec ${directCommand}; fi";

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
  # Per-service process-compose options (added via serviceModules)
  # ---------------------------------------------------------------------------
  processComposeServiceModule =
    { lib, ... }:
    {
      options.process-compose = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether to include this service in process-compose.";
        };
        namespace = lib.mkOption {
          type = lib.types.str;
          default = "services";
          description = "Process-compose namespace for grouping (default: services).";
        };
        readiness_probe = lib.mkOption {
          type = lib.types.nullOr (lib.types.attrsOf lib.types.unspecified);
          default = null;
          description = ''
            Readiness probe configuration. When set, other processes can depend
            on this service with condition = "process_healthy".
          '';
          example = lib.literalExpression ''
            {
              exec.command = "pg_isready -p 5432";
              initial_delay_seconds = 2;
              period_seconds = 5;
            }
          '';
        };
        liveness_probe = lib.mkOption {
          type = lib.types.nullOr (lib.types.attrsOf lib.types.unspecified);
          default = null;
          description = "Liveness probe configuration for health monitoring.";
        };
        availability = lib.mkOption {
          type = lib.types.attrsOf lib.types.unspecified;
          default = {
            restart = "on_failure";
            backoff_seconds = 5;
          };
          description = "Availability/restart policy for the service process.";
        };
        depends_on = lib.mkOption {
          type = lib.types.attrsOf lib.types.unspecified;
          default = { };
          description = "Process dependencies for this service.";
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

      # Get dev command from app.commands.dev or fall back to turbo defaults
      devCommand = app.commands.dev.command or (mkDefaultCommand name app "dev");
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
  mkAppProcessEntries =
    apps:
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
  # Service process entries (from stackpanel.services)
  # ---------------------------------------------------------------------------

  # Generate process-compose entries from stackpanel.services
  mkServiceProcessEntries =
    services:
    let
      enabledServices = lib.filterAttrs (
        _: svc: svc.enable && (svc.process-compose.enable or true)
      ) services;
    in
    lib.mapAttrs (
      name: svc:
      {
        command = svc.command;
        namespace = svc.process-compose.namespace or "services";
      }
      // lib.optionalAttrs (!svc.autoStart) {
        disabled = true;
      }
      // lib.optionalAttrs (svc.process-compose.readiness_probe or null != null) {
        readiness_probe = svc.process-compose.readiness_probe;
      }
      // lib.optionalAttrs (svc.process-compose.liveness_probe or null != null) {
        liveness_probe = svc.process-compose.liveness_probe;
      }
      // lib.optionalAttrs ((svc.process-compose.availability or { }) != { }) {
        availability = svc.process-compose.availability;
      }
      // lib.optionalAttrs ((svc.process-compose.depends_on or { }) != { }) {
        depends_on = svc.process-compose.depends_on;
      }
    ) enabledServices;

  # ---------------------------------------------------------------------------
  # Devenv-compatible process entries (uses exec instead of command)
  # ---------------------------------------------------------------------------
  mkDevenvProcessEntry =
    name: app:
    let
      pcAppCfg = app.process-compose or { };
      # Use explicit null check since pcAppCfg.name can be null (not missing)
      processName = if pcAppCfg.name or null != null then pcAppCfg.name else name;

      # Get dev command from app.commands.dev or fall back to turbo defaults
      devCommand = app.commands.dev.command or (mkDefaultCommand name app "dev");
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
  mkDevenvAppProcessEntries =
    apps:
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
  # Config file generation
  # ---------------------------------------------------------------------------

  # Generate the process-compose config file (YAML format)
  mkConfigFile =
    {
      processes,
      environment,
      commandName,
    }:
    let
      # Convert environment attrset to list of "KEY=VALUE" strings
      envList = lib.mapAttrsToList (k: v: "${k}=${v}") environment;
      configData = {
        version = "0.5";
        inherit processes;
        environment = envList;
        shell = {
          shell_command = "${pkgs.bash}/bin/bash";
          shell_argument = "-c";
        };
      };
      yamlFormat = pkgs.formats.yaml { };
    in
    yamlFormat.generate "process-compose.yaml" configData;

  # ---------------------------------------------------------------------------
  # Package generation
  # ---------------------------------------------------------------------------

  # Build the dev wrapper package
  mkDevPackage =
    {
      processes,
      environment,
      commandName,
      port ? 8080,
    }:
    let
      processCount = builtins.length (lib.attrNames processes);
    in
    pkgs.writeShellScriptBin commandName ''
      if [[ ${toString processCount} -eq 0 ]]; then
        echo "No processes configured for process-compose"
        echo "   Define apps or set stackpanel.process-compose.processes."
        exit 1
      fi

      # Check if we're running inside the devshell
      # IN_NIX_SHELL is set by nix develop, DEVENV_ROOT by devenv
      if [[ -z "''${IN_NIX_SHELL:-}" && -z "''${DEVENV_ROOT:-}" ]]; then
        # Not in devshell - find project root and use ./devshell
        PROJECT_ROOT="''${STACKPANEL_ROOT:-}"
        if [[ -z "$PROJECT_ROOT" ]]; then
          # Try to find it by looking for devshell script
          PROJECT_ROOT="$PWD"
          while [[ "$PROJECT_ROOT" != "/" ]]; do
            if [[ -x "$PROJECT_ROOT/devshell" ]]; then
              break
            fi
            PROJECT_ROOT="$(dirname "$PROJECT_ROOT")"
          done
        fi

        if [[ -x "$PROJECT_ROOT/devshell" ]]; then
          exec "$PROJECT_ROOT/devshell" -- ${commandName} "$@"
        else
          echo "Error: Not in a devshell and could not find ./devshell script" >&2
          echo "Run: nix develop --impure" >&2
          exit 1
        fi
      fi

      # Set PC_PORT_NUM for the process-compose API server
      export PC_PORT_NUM="${toString port}"

      # Run process-compose - auto-detects process-compose.yaml in repo root
      # The --port flag sets the API server port
      exec ${pkgs.process-compose}/bin/process-compose --port ${toString port} "$@"
    '';

in
{
  # ===========================================================================
  # Options
  # ===========================================================================
  options.stackpanel.process-compose = {
    enable = lib.mkEnableOption "process-compose integration" // {
      default = true;
    };

    port = lib.mkOption {
      type = lib.types.nullOr lib.types.port;
      default = null;
      description = ''
        Port for the process-compose API server.
        If null, uses the computed port from stackpanel.ports.service.PROCESS_COMPOSE.port.
        Set PC_PORT_NUM environment variable to this value.
      '';
      example = 8080;
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

  };

  # ===========================================================================
  # Config
  # ===========================================================================
  config = lib.mkMerge [
    # Add the per-app process-compose options to all apps
    {
      stackpanel.appModules = [ processComposeAppModule ];
    }

    # Add the per-service process-compose options to all services
    {
      stackpanel.serviceModules = [ processComposeServiceModule ];
    }

    # When stackpanel is enabled, populate process-compose from apps
    (lib.mkIf cfg.enable {
      # Populate process-compose.processes from apps, services, and infra
      stackpanel.process-compose.processes =
        let
          appProcesses = mkAppProcessEntries cfg.apps;
          serviceProcesses = mkServiceProcessEntries (cfg.services or { });
          infraProcesses = mkInfrastructureProcesses pcCfg.formatWatcher;
        in
        serviceProcesses // appProcesses // infraProcesses;

      # Default environment with ports and devshell env vars
      # Merge devshell.env so services like postgres provide DATABASE_URL to processes
      stackpanel.process-compose.environment =
        (cfg.devshell.env or {})
        // {
          STACKPANEL_PORTS = builtins.toJSON (cfg.ports or { });
        };
    })

    # When process-compose is enabled, build wrapper and add to devshell
    (lib.mkIf (cfg.enable && pcCfg.enable) (
      let
        # Resolve port: explicit config > computed from base port + fixed offset
        # Uses base-port + 90 to avoid hash collisions with other services
        resolvedPort =
          if pcCfg.port != null then
            pcCfg.port
          else
            cfg.ports.base-port + 90;

        configFile = mkConfigFile {
          commandName = pcCfg.commandName;
          processes = pcCfg.processes;
          environment = pcCfg.environment;
        };
      in
      {
        # Set PC_PORT_NUM environment variable for the devshell
        stackpanel.devshell.env.PC_PORT_NUM = toString resolvedPort;

        stackpanel.devshell.packages = [
          pkgs.process-compose
          (mkDevPackage {
            commandName = pcCfg.commandName;
            processes = pcCfg.processes;
            environment = pcCfg.environment;
            port = resolvedPort;
          })
        ];

        # Symlink the config file to repo root (like we do with binaries)
        # process-compose auto-detects process-compose.yaml in the current directory
        stackpanel.files.entries."process-compose.yaml" = {
          enable = true;
          type = "symlink";
          target = "${configFile}";
          description = "Process-compose configuration (symlink to Nix store)";
        };

        # Auto-clean the command alias to avoid conflicts with user's shell aliases
        stackpanel.devshell.clean.aliases = [ pcCfg.commandName ];

        # Register module
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
          tags = meta.tags;
          priority = meta.priority;
        };
      }
    ))

    # Note: We intentionally do NOT populate devenv's `processes` option.
    # Devenv wraps processes with devenv-tasks which adds unnecessary complexity.
    # Instead, we generate our own process-compose.yaml and symlink it to the repo root.
  ];
}
