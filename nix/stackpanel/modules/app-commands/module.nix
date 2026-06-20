# ==============================================================================
# module.nix - App Commands Module Implementation
#
# Nix-native app commands module for stackpanel.
#
# Provides per-app derivations for standard operations (build, dev, test, lint,
# format) exposed as native flake outputs, replacing the npm-script-style
# `tasks` system.
#
# Flake Output Mapping:
#   | Command  | Flake Output          | Access              |
#   |----------|----------------------|---------------------|
#   | build    | packages.<app>       | nix build .#web     |
#   | dev      | packages.<app>-dev   | nix run .#web-dev   |
#   | start    | apps.<app>           | nix run .#web       |
#   | test     | checks.<app>-test    | nix flake check     |
#   | lint     | checks.<app>-lint    | nix flake check     |
#   | format   | checks.<app>-format  | nix flake check     |
#
# Each command supports two modes:
#   1. Package mode - Reference a Nix derivation directly (for builds)
#   2. Script mode - Shell command wrapped with writeShellApplication
#
# Usage:
#   stackpanel.apps.web = {
#     path = "apps/web";
#     type = "bun";
#     commands = {
#       dev = { command = "bun run dev"; runtimeInputs = [ pkgs.bun ]; };
#       build = { package = myBuildDerivation; };
#       test = { command = "bun test"; env.CI = "true"; };
#     };
#   };
# ==============================================================================
{
  lib,
  config,
  pkgs,
  self,
  ...
}:
let
  meta = import ./meta.nix;
  cfg = config.stackpanel;
  portlessCfg = config.stackpanel.portless or { enable = false; };
  portsCfg = config.stackpanel.ports or { project-name = "default"; };
  portsLib = import ../../lib/ports.nix { inherit lib; };

  # Command submodule - defines schema for each command
  commandModule =
    {
      lib,
      name,
      ...
    }:
    {
      options = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = ''
            Whether this app command is enabled.

            Disable a single command while keeping the rest of the app's command
            set available, for example to skip a slow lint check in CI.
          '';
        };

        command = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            Shell command to execute. Mutually exclusive with `package`.
            The command runs from the app's directory (path).
          '';
          example = "bun run dev";
        };

        package = lib.mkOption {
          type = lib.types.nullOr lib.types.package;
          default = null;
          description = ''
            Nix package/derivation to use directly. Mutually exclusive with `command`.
            Use this for pre-built artifacts or complex build derivations.
          '';
          example = lib.literalExpression "pkgs.hello";
        };

        runtimeInputs = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [ ];
          description = ''
            Packages to include in PATH when running the command.

            Use to make command wrappers hermetic instead of relying on the user's
            global shell PATH.
          '';
          example = lib.literalExpression "[ pkgs.bun pkgs.nodejs ]";
        };

        env = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { };
          description = ''
            Environment variables exported while running the command.

            Use for non-secret command defaults. Put secrets in Stackpanel envs or
            SOPS-backed app env declarations.
          '';
          example = {
            NODE_ENV = "development";
            CI = "true";
          };
        };

        description = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            Human-readable description of this command.

            Displayed in generated metadata and used as the derivation/script
            description when Stackpanel wraps shell commands.
          '';
          example = "Run app test suite";
        };

        # Output type determines how the command is exposed
        outputType = lib.mkOption {
          type = lib.types.enum [
            "package"
            "check"
            "app"
          ];
          default =
            if name == "build" then
              "package"
            else if name == "test" || name == "lint" || name == "format" then
              "check"
            else
              "app";
          description = ''
            How this command should be exposed in flake outputs:
            - package: As packages.<app> or packages.<app>-<cmd>
            - check: As checks.<app>-<cmd> (runs during nix flake check)
            - app: As apps.<app> or apps.<app>-<cmd>
          '';
        };
      };
    };

  # Commands submodule - contains all standard commands
  commandsModule = { lib, ... }: {
    options = {
      build = lib.mkOption {
        type = lib.types.nullOr (lib.types.submodule commandModule);
        default = null;
        description = ''
          Build command for a production artifact.

          Exposed as `packages.<app>` when outputType is `package`. Prefer
          `package = <derivation>` for fully Nix-native builds.
        '';
        example = lib.literalExpression ''
          {
            command = "bun run build";
            runtimeInputs = [ pkgs.bun ];
            outputType = "package";
          }
        '';
      };

      dev = lib.mkOption {
        type = lib.types.nullOr (lib.types.submodule commandModule);
        default = null;
        description = ''
          Development server command.

          Exposed as a flake app by default and used by process-compose when
          generating local dev process entries.
        '';
        example = lib.literalExpression ''
          {
            command = "bun run dev";
            runtimeInputs = [ pkgs.bun ];
          }
        '';
      };

      start = lib.mkOption {
        type = lib.types.nullOr (lib.types.submodule commandModule);
        default = null;
        description = ''
          Start the app in production mode.

          Use for `nix run .#<app>` style launches and systemd ExecStart command
          generation when deployment modules need an explicit runtime command.
        '';
      };

      test = lib.mkOption {
        type = lib.types.nullOr (lib.types.submodule commandModule);
        default = null;
        description = ''
          Test command for this app.

          Exposed as `checks.<app>-test` by default so it participates in
          `nix flake check`.
        '';
        example = lib.literalExpression ''
          { command = "bun test"; env.CI = "true"; }
        '';
      };

      lint = lib.mkOption {
        type = lib.types.nullOr (lib.types.submodule commandModule);
        default = null;
        description = ''
          Lint command for this app.

          Exposed as `checks.<app>-lint` by default and can be consumed by git
          hook aggregation.
        '';
        example = lib.literalExpression ''
          { command = "bun run lint"; }
        '';
      };

      format = lib.mkOption {
        type = lib.types.nullOr (lib.types.submodule commandModule);
        default = null;
        description = ''
          Formatter command for this app, expected to run in check mode for CI.

          Use a separate local fix command if the formatter mutates files.
        '';
        example = lib.literalExpression ''
          { command = "bun run format:check"; }
        '';
      };
    };
  };

  # ===========================================================================
  # Derivation builders
  # ===========================================================================

  # Build a script derivation from a command definition
  mkCommandScript =
    appName: appCfg: cmdName: cmdCfg:
    let
      appPath = appCfg.path or ".";
      envExports = lib.concatStringsSep "\n" (
        lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg v}") (cmdCfg.env or { })
      );

      # Portless prefix for `dev` commands when portless is enabled and the
      # app has a domain. Uses --app-port to pin the deterministic port so
      # other services that reference the port env var still work.
      usePortless = cmdName == "dev" && portlessCfg.enable && (appCfg.domain or null) != null;
      appPort = portsLib.stablePort {
        repo = cfg.apps.github or "darkmatter/stackpanel";
        service = appName;
      };
      portlessName = "${appCfg.domain}.${portlessCfg.project-name or portsCfg.project-name}";
      execLine =
        if usePortless then
          "exec portless ${portlessName} --app-port ${toString appPort} ${cmdCfg.command}"
        else
          "exec ${cmdCfg.command}";
    in
    pkgs.writeShellApplication {
      name = "${appName}-${cmdName}";
      runtimeInputs = cmdCfg.runtimeInputs or [ ];
      text = ''
        # Change to app directory
        ROOT="''${STACKPANEL_ROOT:-$(pwd)}"
        cd "$ROOT/${appPath}"

        # Set environment variables
        ${envExports}

        # Execute command
        ${execLine}
      '';
      meta = {
        description = cmdCfg.description or "${cmdName} command for ${appName}";
      };
    };

  # Build a check derivation (runs command and fails if non-zero exit)
  mkCheckDerivation =
    appName: appCfg: cmdName: cmdCfg:
    let
      appPath = appCfg.path or ".";
      repoRoot = self.outPath;
      envExports = lib.concatStringsSep "\n" (
        lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg v}") (cmdCfg.env or { })
      );
    in
    pkgs.runCommand "${appName}-${cmdName}"
      {
        nativeBuildInputs = cmdCfg.runtimeInputs or [ ];
        src = repoRoot;
      }
      ''
        cd $src/${appPath}

        # Set environment variables
        ${envExports}

        # Run the check command
        ${cmdCfg.command}

        # Create output marker
        touch $out
      '';

  # Get the derivation for a command (either provided package or generated script)
  getCommandDrv =
    appName: appCfg: cmdName: cmdCfg:
    if cmdCfg.package != null then
      cmdCfg.package
    else if cmdCfg.command != null then
      if cmdCfg.outputType == "check" then
        mkCheckDerivation appName appCfg cmdName cmdCfg
      else
        mkCommandScript appName appCfg cmdName cmdCfg
    else
      null;

  # ===========================================================================
  # Output collection
  # ===========================================================================

  # Collect all outputs for a single app
  collectAppOutputs =
    appName: appCfg:
    let
      # Handle both missing and null commands
      rawCommands = appCfg.commands or null;
      commands = if rawCommands == null then { } else rawCommands;
      enabledCommands = lib.filterAttrs (
        _: cmd: cmd != null && (cmd.enable or true) && (cmd.command != null || cmd.package != null)
      ) commands;

      # Build output for each command
      mkOutput =
        cmdName: cmdCfg:
        let
          drv = getCommandDrv appName appCfg cmdName cmdCfg;
          outputType = cmdCfg.outputType or "app";
        in
        if drv == null then
          null
        else
          {
            inherit drv outputType;
            name =
              if cmdName == "build" then
                appName
              else if cmdName == "start" then
                appName
              else
                "${appName}-${cmdName}";
          };

      outputs = lib.mapAttrs mkOutput enabledCommands;
      validOutputs = lib.filterAttrs (_: v: v != null) outputs;

      # Separate by output type
      packages = lib.filterAttrs (_: v: v.outputType == "package") validOutputs;
      checks = lib.filterAttrs (_: v: v.outputType == "check") validOutputs;
      apps = lib.filterAttrs (_: v: v.outputType == "app") validOutputs;

      # Convert to output format, using the computed name as key
      mkOutputWithName =
        outputs:
        lib.listToAttrs (
          lib.mapAttrsToList (_cmdName: v: {
            inherit (v) name; # Use the computed name (e.g., "web-dev" not "dev")
            value = v.drv;
          }) outputs
        );
      mkAppsWithName =
        outputs:
        lib.listToAttrs (
          lib.mapAttrsToList (_cmdName: v: {
            inherit (v) name;
            value = {
              type = "app";
              program = lib.getExe v.drv;
            };
          }) outputs
        );
    in
    {
      packages = mkOutputWithName packages;
      checks = mkOutputWithName checks;
      apps = mkAppsWithName apps;
    };
in
{
  # ===========================================================================
  # Configuration
  # ===========================================================================
  config = lib.mkMerge [
    # Add commands option to all apps via appModules
    {
      stackpanel.appModules = [
        ({ lib, ... }: {
          options.commands = lib.mkOption {
            type = lib.types.nullOr (lib.types.submodule commandsModule);
            default = null;
            description = ''
              Nix-native commands for this app.

              Each command becomes a flake output:
              - build -> packages.<app>
              - dev -> packages.<app>-dev (runnable script)
              - start -> apps.<app>
              - test/lint/format -> checks.<app>-<cmd>

              Commands support two modes:
              - command: Shell command (wrapped with writeShellApplication)
              - package: Pre-built Nix derivation
            '';
            example = lib.literalExpression ''
              {
                dev = { command = "bun run dev"; runtimeInputs = [ pkgs.bun ]; };
                build = { command = "bun run build"; runtimeInputs = [ pkgs.bun ]; };
                test = { command = "bun test"; env.CI = "true"; };
              }
            '';
          };
        })
      ];
    }

    # Generate outputs when apps have commands defined
    # NOTE: Compute app-related values lazily here inside the config block
    (
      let
        # Filter apps that have commands defined
        # Handle both missing and null commands
        appsWithCommands = lib.filterAttrs (
          _: app:
          let
            cmds = app.commands or null;
          in
          cmds != null && cmds != { }
        ) cfg.apps;

        # Collect outputs from all apps
        allAppOutputs = lib.mapAttrs collectAppOutputs appsWithCommands;

        # Build healthchecks from app check commands
        appCheckModules = lib.mapAttrs' (
          appName: appCfg:
          let
            rawCommands = appCfg.commands or null;
            commands = if rawCommands == null then { } else rawCommands;
            checkCommands = lib.filterAttrs (
              _: cmd:
              cmd != null && (cmd.enable or true) && (cmd.outputType or "app") == "check" && cmd.command != null
            ) commands;

            mkCheck = cmdName: cmdCfg: {
              name = cmdCfg.description or "${appName} ${cmdName}";
              description = cmdCfg.description or "App check command";
              type = "script";
              severity = "warning";
              scriptPackage = mkCommandScript appName appCfg cmdName cmdCfg;
            };
          in
          if checkCommands == { } then
            lib.nameValuePair "app-${appName}" {
              enable = false;
              checks = { };
              displayName = appName;
            }
          else
            lib.nameValuePair "app-${appName}" {
              enable = true;
              displayName = "${appName} checks";
              checks = lib.mapAttrs mkCheck checkCommands;
            }
        ) appsWithCommands;

        # Merge all outputs
        mergedPackages = lib.foldl' (acc: outputs: acc // outputs.packages) { } (
          lib.attrValues allAppOutputs
        );

        mergedChecks = lib.foldl' (acc: outputs: acc // outputs.checks) { } (lib.attrValues allAppOutputs);

        mergedApps = lib.foldl' (acc: outputs: acc // outputs.apps) { } (lib.attrValues allAppOutputs);

        hasAppsWithCommands = appsWithCommands != { };
      in
      lib.mkIf hasAppsWithCommands {
        # Expose packages via stackpanel.outputs
        stackpanel.outputs = mergedPackages;

        # Expose checks via stackpanel.checks
        stackpanel.checks = mergedChecks;

        # Expose apps via stackpanel.flakeApps (for nix run .#<name>)
        stackpanel.flakeApps = mergedApps;

        # Register app check commands as healthchecks
        stackpanel.healthchecks.modules = appCheckModules;

        # Register module
        stackpanel.modules.${meta.id} = {
          enable = true;
          meta = {
            inherit (meta) name;
            inherit (meta) description;
            inherit (meta) icon;
            inherit (meta) category;
            inherit (meta) author;
            inherit (meta) version;
            inherit (meta) homepage;
          };
          source.type = "builtin";
          inherit (meta) features;
          flakeInputs = meta.flakeInputs or [ ];
          inherit (meta) tags;
          inherit (meta) priority;
        };
      }
    )
  ];
}
