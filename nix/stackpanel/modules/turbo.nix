# ==============================================================================
# turbo.nix
#
# Turborepo integration for stackpanel.
#
# This module:
#   1. Generates turbo.json from stackpanel.tasks
#   2. Compiles task scripts with `exec` to Nix derivations
#   3. Creates symlinks in .tasks/bin/ for Turborepo to invoke
#   4. Generates package.json script entries
#   5. Handles per-app task overrides via stackpanel.apps.*.tasks
#
# Architecture:
#   - Tasks with `exec` become writeShellApplication derivations
#   - Derivations are symlinked to .tasks/bin/<task>
#   - package.json scripts call ./.tasks/bin/<task>
#   - turbo.json references task names with deps/outputs/caching
#
# Usage:
#   stackpanel.tasks = {
#     build = {
#       exec = "npm run compile";
#       after = [ "deps" "^build" ];
#       outputs = [ "dist/**" ];
#       runtimeInputs = [ pkgs.nodejs ];
#     };
#     dev = {
#       persistent = true;
#       cache = false;
#     };
#   };
# ==============================================================================
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.stackpanel;
  tasksCfg = cfg.tasks;
  # NOTE: Do NOT define appsCfg here - it causes infinite recursion when
  # combined with appModules. Access cfg.apps only inside mkIf blocks.

  # ---------------------------------------------------------------------------
  # Per-app task options module (added via appModules)
  # ---------------------------------------------------------------------------
  taskAppModule =
    { lib, ... }:
    {
      options.turbo = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether to include this app in turbo.json generation.";
        };
      };
    };

  # ---------------------------------------------------------------------------
  # Helper: Create task script derivation
  # ---------------------------------------------------------------------------
  mkTaskScript =
    taskName: taskCfg:
    let
      hasExec = taskCfg.exec or null != null;
    in
    if !hasExec then
      null
    else
      pkgs.writeShellApplication {
        name = taskName;
        runtimeInputs = taskCfg.runtimeInputs or [ ];
        text = ''
          # Task: ${taskName}
          ${lib.optionalString (taskCfg.description or null != null) "# ${taskCfg.description}"}

          # Change to working directory if specified
          ${lib.optionalString (taskCfg.cwd or null != null) ''
            cd "''${STACKPANEL_ROOT:-$(pwd)}/${taskCfg.cwd}"
          ''}

          # Set task-specific environment variables
          ${lib.concatStringsSep "\n" (
            lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg v}") (taskCfg.env or { })
          )}

          # Execute task
          ${taskCfg.exec}
        '';
      };

  # ---------------------------------------------------------------------------
  # Helper: Create app-level task script derivation
  # ---------------------------------------------------------------------------
  mkAppTaskScript =
    appName: appCfg: taskName: taskCfg:
    let
      hasExec = taskCfg.exec or null != null;
      appPath = appCfg.path or "apps/${appName}";
    in
    if !hasExec then
      null
    else
      pkgs.writeShellApplication {
        name = "${appName}-${taskName}";
        runtimeInputs = taskCfg.runtimeInputs or [ ];
        text = ''
          # App: ${appName}, Task: ${taskName}
          ${lib.optionalString (taskCfg.description or null != null) "# ${taskCfg.description}"}

          # Change to app directory
          cd "''${STACKPANEL_ROOT:-$(pwd)}/${taskCfg.cwd or appPath}"

          # Set task-specific environment variables
          ${lib.concatStringsSep "\n" (
            lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg v}") (taskCfg.env or { })
          )}

          # Execute task
          ${taskCfg.exec}
        '';
      };

  # ---------------------------------------------------------------------------
  # Compute reverse dependencies (before -> dependsOn)
  # ---------------------------------------------------------------------------
  # Build a map: taskName -> list of tasks that should run before it
  computeReverseDeps =
    tasks:
    let
      # For each task, if it has `before = [ "x" "y" ]`, add this task to x and y's deps
      addReverseDeps =
        acc: taskName: taskCfg:
        lib.foldl' (
          innerAcc: targetTask:
          innerAcc
          // {
            ${targetTask} = (innerAcc.${targetTask} or [ ]) ++ [ taskName ];
          }
        ) acc (taskCfg.before or [ ]);
    in
    lib.foldl' (acc: taskName: addReverseDeps acc taskName tasks.${taskName}) { } (lib.attrNames tasks);

  reverseDeps = computeReverseDeps tasksCfg;

  # ---------------------------------------------------------------------------
  # Generate turbo.json task entry
  # ---------------------------------------------------------------------------
  mkTurboTask =
    taskName: taskCfg:
    let
      # Combine explicit `dependsOn` with reverse deps from other tasks' `before`
      explicitDeps = taskCfg.dependsOn or [ ];
      reverseDepsForTask = reverseDeps.${taskName} or [ ];
      allDeps = explicitDeps ++ reverseDepsForTask;

      # Build the task config, omitting empty/default values
      taskConfig =
        { }
        // lib.optionalAttrs (allDeps != [ ]) { dependsOn = allDeps; }
        // lib.optionalAttrs ((taskCfg.outputs or [ ]) != [ ]) { outputs = taskCfg.outputs; }
        // lib.optionalAttrs ((taskCfg.inputs or [ ]) != [ ]) { inputs = taskCfg.inputs; }
        // lib.optionalAttrs (taskCfg.cache or null == false) { cache = false; }
        // lib.optionalAttrs (taskCfg.persistent or null == true) { persistent = true; }
        // lib.optionalAttrs (taskCfg.interactive or null == true) { interactive = true; };
    in
    taskConfig;

  # ---------------------------------------------------------------------------
  # Generate workspace-level turbo.json
  # ---------------------------------------------------------------------------
  turboConfig = {
    "$schema" = "https://turbo.build/schema.json";
    ui = "tui";
    tasks = lib.mapAttrs mkTurboTask tasksCfg;
  };

  turboJsonText = builtins.toJSON turboConfig;

  # ---------------------------------------------------------------------------
  # Generate task scripts and symlink file entries
  # ---------------------------------------------------------------------------
  taskScripts = lib.filterAttrs (_: v: v != null) (lib.mapAttrs mkTaskScript tasksCfg);

  # File entries for .tasks/bin/ symlinks
  taskSymlinkEntries = lib.mapAttrs' (
    taskName: scriptDrv: {
      name = ".tasks/bin/${taskName}";
      value = {
        type = "symlink";
        target = "${scriptDrv}/bin/${taskName}";
        source = "turbo.nix";
        description = "Task script for ${taskName}";
      };
    }
  ) taskScripts;

  # ---------------------------------------------------------------------------
  # Helper functions for per-app turbo.json and task scripts
  # NOTE: These are functions, not values - they're called lazily inside mkIf
  # ---------------------------------------------------------------------------

  # Per-app task scripts
  mkAppTaskScripts =
    appName: appCfg:
    let
      appTasks = appCfg.tasks or { };
    in
    lib.filterAttrs (_: v: v != null) (
      lib.mapAttrs (mkAppTaskScript appName appCfg) appTasks
    );

  # Per-app turbo.json content
  mkAppTurboConfig =
    appName: appCfg:
    let
      appTasks = appCfg.tasks or { };
      appTaskConfigs = lib.mapAttrs (
        taskName: taskCfg:
        let
          explicitDeps = taskCfg.dependsOn or [ ];
          taskConfig =
            { }
            // lib.optionalAttrs (explicitDeps != [ ]) { dependsOn = explicitDeps; }
            // lib.optionalAttrs ((taskCfg.outputs or [ ]) != [ ]) { outputs = taskCfg.outputs; };
        in
        taskConfig
      ) appTasks;
    in
    {
      extends = [ "//" ];
      tasks = appTaskConfigs;
    };

  # Per-app file entries generator
  mkAppFileEntries =
    appsWithTasks: appTaskScripts: appTurboConfigs: appName: appCfg:
    let
      appPath = appCfg.path or "apps/${appName}";
      scripts = appTaskScripts.${appName} or { };

      # turbo.json for this app
      turboEntry = {
        "${appPath}/turbo.json" = {
          type = "text";
          text = builtins.toJSON (appTurboConfigs.${appName});
          source = "turbo.nix";
          description = "Per-package turbo.json for ${appName}";
        };
      };

      # .tasks/bin/ symlinks for this app
      symlinkEntries = lib.mapAttrs' (
        taskName: scriptDrv: {
          name = "${appPath}/.tasks/bin/${taskName}";
          value = {
            type = "symlink";
            target = "${scriptDrv}/bin/${appName}-${taskName}";
            source = "turbo.nix";
            description = "Task script for ${appName}:${taskName}";
          };
        }
      ) scripts;
    in
    turboEntry // symlinkEntries;

  # ---------------------------------------------------------------------------
  # Generate package.json script entries
  # Scripts are simple wrappers calling .tasks/bin/<task>
  # ---------------------------------------------------------------------------
  packageJsonScripts = lib.mapAttrs (
    taskName: _scriptDrv: "./.tasks/bin/${taskName}"
  ) taskScripts;

  # Check if we have any tasks defined
  hasTasks = tasksCfg != { };

in
{
  # ===========================================================================
  # Options
  # ===========================================================================
  options.stackpanel.turbo = {
    enable = lib.mkEnableOption "Turborepo integration" // {
      default = true;
    };

    ui = lib.mkOption {
      type = lib.types.enum [
        "tui"
        "stream"
      ];
      default = "tui";
      description = "Turborepo UI mode.";
    };

    envMode = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.enum [
          "strict"
          "loose"
        ]
      );
      default = null;
      description = "Turborepo environment mode. If null, uses Turborepo default.";
    };

    # Read-only computed outputs
    config = lib.mkOption {
      type = lib.types.attrs;
      readOnly = true;
      description = "Generated turbo.json configuration.";
    };

    scripts = lib.mkOption {
      type = lib.types.attrsOf lib.types.package;
      readOnly = true;
      description = "Generated task script derivations.";
    };

    packageJsonScripts = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      readOnly = true;
      description = "Package.json script entries to merge.";
    };
  };

  # ===========================================================================
  # Config
  # ===========================================================================
  config = lib.mkMerge [
    # Add per-app turbo options via appModules
    {
      stackpanel.appModules = [ taskAppModule ];
    }

    # When stackpanel is enabled and has tasks, generate outputs
    (lib.mkIf (cfg.enable && hasTasks) {
      # Expose computed values
      stackpanel.turbo.config = turboConfig;
      stackpanel.turbo.scripts = taskScripts;
      stackpanel.turbo.packageJsonScripts = packageJsonScripts;

      # Populate tasksComputed with generated derivations
      stackpanel.tasksComputed = lib.mapAttrs (
        taskName: taskCfg: {
          script = taskScripts.${taskName} or null;
          turboConfig = mkTurboTask taskName taskCfg;
          dependsOn = (taskCfg.dependsOn or [ ]) ++ (reverseDeps.${taskName} or [ ]);
        }
      ) tasksCfg;

      # Generate files via stackpanel.files system (workspace-level only)
      stackpanel.files.entries = lib.mkMerge [
        # Root turbo.json
        {
          "turbo.json" = {
            type = "text";
            text = turboJsonText;
            source = "turbo.nix";
            description = "Turborepo pipeline configuration";
          };
        }

        # .tasks/bin/ symlinks for workspace-level tasks
        taskSymlinkEntries
      ];

      # Add turbo to devshell packages
      stackpanel.devshell.packages = [ pkgs.turbo ];

      # Add .tasks/ to gitignore reminder in MOTD
      stackpanel.motd.commands = lib.mkIf (taskScripts != { }) [
        {
          name = "Tasks:";
          description = lib.concatStringsSep ", " (lib.attrNames taskScripts);
        }
      ];
    })

    # Per-app turbo files - computed lazily to avoid recursion with appModules
    (
      let
        # Access cfg.apps here inside the config block, not at module top-level
        appsWithTasks = lib.filterAttrs (
          _: appCfg: (appCfg.tasks or { }) != { } && (appCfg.turbo.enable or true)
        ) cfg.apps;

        hasAppsWithTasks = appsWithTasks != { };

        # Compute app-specific values only when needed
        appTaskScripts = lib.mapAttrs mkAppTaskScripts appsWithTasks;
        appTurboConfigs = lib.mapAttrs mkAppTurboConfig appsWithTasks;
        appFileEntries = lib.foldl' (
          acc: appName: acc // (mkAppFileEntries appsWithTasks appTaskScripts appTurboConfigs appName appsWithTasks.${appName})
        ) { } (lib.attrNames appsWithTasks);
      in
      lib.mkIf (cfg.enable && hasAppsWithTasks) {
        stackpanel.files.entries = appFileEntries;
      }
    )
  ];
}
