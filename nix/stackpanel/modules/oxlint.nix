# ==============================================================================
# oxlint.nix
#
# OxLint integration for JavaScript/TypeScript linting.
#
# OxLint (https://oxc.rs) is a blazing fast JavaScript/TypeScript linter
# written in Rust. This module provides:
#
#   1. Devshell packages (oxlint)
#   2. Per-app linting configuration via stackpanel.apps.*.linting.oxlint
#   3. Config file generation (.oxlintrc.json)
#   4. Shell scripts (lint, lint:fix)
#   5. Git hooks integration (pre-commit linting)
#   6. Turbo task integration
#   7. Health checks
#   8. UI panel for lint status
#
# Usage:
#   stackpanel.apps.web = {
#     linting.oxlint = {
#       enable = true;
#       configPath = ".oxlintrc.json";  # optional, auto-generated if not provided
#       plugins = [ "react" "typescript" ];
#       rules = {
#         "no-console" = "warn";
#         "no-debugger" = "error";
#       };
#       ignorePatterns = [ "dist" "node_modules" "*.min.js" ];
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

  # ---------------------------------------------------------------------------
  # Per-app linting options module (added via appModules)
  # ---------------------------------------------------------------------------
  oxlintAppModule =
    { lib, name, ... }:
    {
      options.linting = {
        oxlint = {
          enable = lib.mkEnableOption "OxLint for JavaScript/TypeScript linting";

          package = lib.mkOption {
            type = lib.types.package;
            default = pkgs.oxlint;
            defaultText = lib.literalExpression "pkgs.oxlint";
            description = "The oxlint package to use.";
          };

          configPath = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = ''
              Path to oxlint config file relative to app root.
              If null, a config file will be generated at `.oxlintrc.json`.
            '';
            example = "oxlint.json";
          };

          plugins = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "OxLint plugins to enable.";
            example = [
              "react"
              "typescript"
              "import"
              "jsx-a11y"
            ];
          };

          categories = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = {
              correctness = "error";
              suspicious = "warn";
              pedantic = "off";
              style = "off";
              nursery = "off";
            };
            description = "Rule category severity levels.";
          };

          rules = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = { };
            description = "Individual rule overrides. Values: 'off', 'warn', 'error'.";
            example = {
              "no-console" = "warn";
              "no-debugger" = "error";
              "eqeqeq" = "error";
            };
          };

          ignorePatterns = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [
              "node_modules"
              "dist"
              "build"
              ".next"
              "coverage"
              "*.min.js"
              "*.bundle.js"
            ];
            description = "Glob patterns to ignore.";
          };

          paths = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [
              "src"
              "."
            ];
            description = "Paths to lint (relative to app root).";
          };

          fix = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Whether to automatically fix fixable issues by default.";
          };

          gitHook = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether to run oxlint in pre-commit git hook.";
          };

          turboTask = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = ''
              Deprecated: This option is no longer used.
              Turbo tasks are managed by the turbo module. Configure your
              package.json to run oxlint as part of your lint script.
            '';
          };
        };
      };
    };

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Get apps with oxlint enabled
  oxlintApps = lib.filterAttrs (_: app: app.linting.oxlint.enable or false) (cfg.apps or { });

  hasOxlintApps = oxlintApps != { };

  # Generate oxlint config for an app
  mkOxlintConfig =
    name: appCfg:
    let
      oxCfg = appCfg.linting.oxlint;
    in
    {
      "$schema" =
        "https://raw.githubusercontent.com/oxc-project/oxc/main/npm/oxlint/configuration_schema.json";
      plugins = oxCfg.plugins;
      categories = oxCfg.categories;
      rules = lib.mapAttrs (rule: level: level) oxCfg.rules;
      ignorePatterns = oxCfg.ignorePatterns;
    };

  # Create wrapped linter script for git hooks
  mkWrappedLinter =
    name: appCfg:
    let
      oxCfg = appCfg.linting.oxlint;
      appPath = appCfg.path or "apps/${name}";
      configArg = if oxCfg.configPath != null then "-c ${oxCfg.configPath}" else "-c .oxlintrc.json";
    in
    pkgs.writeShellApplication {
      name = "oxlint-${name}";
      runtimeInputs = [ oxCfg.package ];
      text = ''
        cd "''${STACKPANEL_ROOT:-.}/${appPath}"
        oxlint ${configArg} ${lib.concatStringsSep " " oxCfg.paths}
      '';
    };

  # Create lint:fix script for an app
  mkLintFixScript =
    name: appCfg:
    let
      oxCfg = appCfg.linting.oxlint;
      appPath = appCfg.path or "apps/${name}";
      configArg = if oxCfg.configPath != null then "-c ${oxCfg.configPath}" else "-c .oxlintrc.json";
    in
    pkgs.writeShellApplication {
      name = "oxlint-fix-${name}";
      runtimeInputs = [ oxCfg.package ];
      text = ''
        cd "''${STACKPANEL_ROOT:-.}/${appPath}"
        oxlint ${configArg} --fix ${lib.concatStringsSep " " oxCfg.paths}
      '';
    };

  # Build file entries for config generation
  mkConfigFileEntries = lib.concatMapAttrs (
    name: appCfg:
    let
      oxCfg = appCfg.linting.oxlint;
      appPath = appCfg.path or "apps/${name}";
      configFileName = if oxCfg.configPath != null then oxCfg.configPath else ".oxlintrc.json";
    in
    # Only generate if no custom config path provided
    lib.optionalAttrs (oxCfg.configPath == null) {
      "${appPath}/${configFileName}" = {
        type = "text";
        text = builtins.toJSON (mkOxlintConfig name appCfg);
        description = "OxLint configuration for ${name}";
        source = "oxlint";
      };
    }
  ) oxlintApps;

  # Build scripts
  mkScripts = lib.concatMapAttrs (
    name: appCfg:
    let
      oxCfg = appCfg.linting.oxlint;
      appPath = appCfg.path or "apps/${name}";
      configArg = if oxCfg.configPath != null then "-c ${oxCfg.configPath}" else "-c .oxlintrc.json";
      paths = lib.concatStringsSep " " oxCfg.paths;
    in
    {
      "lint-${name}" = {
        exec = ''
          cd "$STACKPANEL_ROOT/${appPath}"
          oxlint ${configArg} ${paths}
        '';
        runtimeInputs = [ oxCfg.package ];
        description = "Lint ${name} with OxLint";
      };
      "lint-${name}-fix" = {
        exec = ''
          cd "$STACKPANEL_ROOT/${appPath}"
          oxlint ${configArg} --fix ${paths}
        '';
        runtimeInputs = [ oxCfg.package ];
        description = "Lint and fix ${name} with OxLint";
      };
    }
  ) oxlintApps;

  # Build turbo tasks
  mkTurboTasks = lib.concatMapAttrs (
    name: appCfg:
    let
      oxCfg = appCfg.linting.oxlint;
    in
    lib.optionalAttrs oxCfg.turboTask {
      "lint" = {
        description = "Lint with OxLint";
        dependsOn = [ ];
        outputs = [ ];
        cache = true;
      };
    }
  ) oxlintApps;

  # Collect linters for git hooks
  allLinters = lib.flatten (
    lib.mapAttrsToList (
      name: appCfg:
      let
        oxCfg = appCfg.linting.oxlint;
      in
      lib.optional oxCfg.gitHook (mkWrappedLinter name appCfg)
    ) oxlintApps
  );

in
{
  # Use lib.mkMerge to combine multiple config blocks
  config = lib.mkMerge [
    # Always add per-app options (not conditional)
    {
      stackpanel.appModules = [ oxlintAppModule ];
    }

    # Apply configuration when oxlint apps exist
    (
      let
        # Re-evaluate inside the mkMerge block to avoid referencing before definition
        oxlintAppsLocal = lib.filterAttrs (_: app: app.linting.oxlint.enable or false) (cfg.apps or { });
        hasOxlintAppsLocal = oxlintAppsLocal != { };
      in
      lib.mkIf (cfg.enable && hasOxlintAppsLocal) {
        # Add oxlint to devshell packages
        stackpanel.devshell.packages = lib.unique (
          lib.mapAttrsToList (_: appCfg: appCfg.linting.oxlint.package) oxlintAppsLocal
        );

        # Generate config files
        stackpanel.files.entries = lib.concatMapAttrs (
          name: appCfg:
          let
            oxCfg = appCfg.linting.oxlint;
            appPath = appCfg.path or "apps/${name}";
            configFileName = if oxCfg.configPath != null then oxCfg.configPath else ".oxlintrc.json";
          in
          # Only generate if no custom config path provided
          lib.optionalAttrs (oxCfg.configPath == null) {
            "${appPath}/${configFileName}" = {
              type = "text";
              text = builtins.toJSON (mkOxlintConfig name appCfg);
              description = "OxLint configuration for ${name}";
              source = "oxlint";
            };
          }
        ) oxlintAppsLocal;

        # Add per-app scripts + global lint scripts
        stackpanel.scripts = lib.mkMerge [
          # Per-app lint scripts
          (lib.concatMapAttrs (
            name: appCfg:
            let
              oxCfg = appCfg.linting.oxlint;
              appPath = appCfg.path or "apps/${name}";
              configArg = if oxCfg.configPath != null then "-c ${oxCfg.configPath}" else "-c .oxlintrc.json";
              paths = lib.concatStringsSep " " oxCfg.paths;
            in
            {
              "lint-${name}" = {
                exec = ''
                  cd "$STACKPANEL_ROOT/${appPath}"
                  oxlint ${configArg} ${paths}
                '';
                runtimeInputs = [ oxCfg.package ];
                description = "Lint ${name} with OxLint";
              };
              "lint-${name}-fix" = {
                exec = ''
                  cd "$STACKPANEL_ROOT/${appPath}"
                  oxlint ${configArg} --fix ${paths}
                '';
                runtimeInputs = [ oxCfg.package ];
                description = "Lint and fix ${name} with OxLint";
              };
            }
          ) oxlintAppsLocal)

          # Global lint scripts
          (lib.mkIf (builtins.length (lib.attrNames oxlintAppsLocal) > 0) {
            "lint" = {
              exec = ''
                echo "Running OxLint on all apps..."
                exit_code=0
                ${lib.concatMapStringsSep "\n" (name: ''
                  echo "Linting ${name}..."
                  lint-${name} || exit_code=$?
                '') (lib.attrNames oxlintAppsLocal)}
                exit "$exit_code"
              '';
              description = "Lint all apps with OxLint";
            };
            "lint-fix" = {
              exec = ''
                echo "Running OxLint --fix on all apps..."
                ${lib.concatMapStringsSep "\n" (name: ''
                  echo "Fixing ${name}..."
                  lint-${name}-fix
                '') (lib.attrNames oxlintAppsLocal)}
              '';
              description = "Lint and fix all apps with OxLint";
            };
          })
        ];

        # NOTE: We don't define stackpanel.tasks.lint here because turbo.nix already
        # provides a generic lint task. OxLint integrates via:
        # 1. Shell scripts (lint, lint-fix, lint-<app>) for direct use
        # 2. Git hooks via extraLinters for pre-commit
        # 3. Apps can configure package.json scripts to use oxlint with turbo

        # Add linters for git hooks via extraLinters (avoids infinite recursion)
        # These are wrapped shell scripts that can be run by git-hooks.nix
        stackpanel.git-hooks.extraLinters = lib.flatten (
          lib.mapAttrsToList (
            name: appCfg:
            let
              oxCfg = appCfg.linting.oxlint;
            in
            lib.optional oxCfg.gitHook (mkWrappedLinter name appCfg)
          ) oxlintAppsLocal
        );

        # Health checks
        stackpanel.healthchecks.modules.oxlint = {
          enable = true;
          displayName = "OxLint";
          checks = {
            oxlint-installed = {
              description = "OxLint is installed and accessible";
              script = ''
                if command -v oxlint >/dev/null 2>&1; then
                  version=$(oxlint --version 2>&1 | head -1)
                  echo "OxLint version: $version"
                  exit 0
                else
                  echo "OxLint is not installed"
                  exit 1
                fi
              '';
              severity = "critical";
              timeout = 5;
            };
            oxlint-config = {
              description = "OxLint configuration files exist";
              script = ''
                missing=""
                ${lib.concatMapStringsSep "\n" (
                  name:
                  let
                    appCfg = oxlintAppsLocal.${name};
                    appPath = appCfg.path or "apps/${name}";
                    configFile =
                      if appCfg.linting.oxlint.configPath != null then
                        appCfg.linting.oxlint.configPath
                      else
                        ".oxlintrc.json";
                  in
                  ''
                    if [ ! -f "$STACKPANEL_ROOT/${appPath}/${configFile}" ]; then
                      missing="$missing ${name}"
                    fi
                  ''
                ) (lib.attrNames oxlintAppsLocal)}
                if [ -n "$missing" ]; then
                  echo "Missing config for:$missing"
                  exit 1
                fi
                echo "All OxLint configs present"
              '';
              severity = "warning";
              timeout = 5;
            };
            oxlint-passes = {
              description = "OxLint check passes on all apps";
              script = ''
                failed=""
                ${lib.concatMapStringsSep "\n" (
                  name:
                  let
                    appCfg = oxlintAppsLocal.${name};
                    appPath = appCfg.path or "apps/${name}";
                    oxCfg = appCfg.linting.oxlint;
                    configArg = if oxCfg.configPath != null then "-c ${oxCfg.configPath}" else "-c .oxlintrc.json";
                    paths = lib.concatStringsSep " " oxCfg.paths;
                  in
                  ''
                    if ! (cd "$STACKPANEL_ROOT/${appPath}" && oxlint ${configArg} ${paths} 2>/dev/null); then
                      failed="$failed ${name}"
                    fi
                  ''
                ) (lib.attrNames oxlintAppsLocal)}
                if [ -n "$failed" ]; then
                  echo "Lint failed for:$failed"
                  exit 1
                fi
                echo "All apps pass linting"
              '';
              severity = "warning";
              timeout = 60;
            };
          };
        };

        # UI Panel
        stackpanel.panels.oxlint-status = {
          module = "oxlint";
          title = "OxLint Status";
          description = "JavaScript/TypeScript linting with OxLint";
          type = "PANEL_TYPE_STATUS";
          order = 50;
          fields = [
            {
              name = "apps";
              type = "FIELD_TYPE_JSON";
              value = builtins.toJSON (
                lib.mapAttrsToList (name: appCfg: {
                  name = name;
                  path = appCfg.path or "apps/${name}";
                  plugins = appCfg.linting.oxlint.plugins;
                  gitHook = appCfg.linting.oxlint.gitHook;
                  turboTask = appCfg.linting.oxlint.turboTask;
                }) oxlintAppsLocal
              );
            }
            {
              name = "commands";
              type = "FIELD_TYPE_JSON";
              value = builtins.toJSON [
                {
                  name = "lint";
                  description = "Run OxLint on all apps";
                }
                {
                  name = "lint-fix";
                  description = "Run OxLint --fix on all apps";
                }
              ];
            }
          ];
        };

        # Register as a stackpanel module
        stackpanel.modules.oxlint = {
          enable = true;
          meta = {
            name = "OxLint";
            description = "Blazing fast JavaScript/TypeScript linter";
            icon = "search-code";
            category = "development";
            author = "Stackpanel";
            version = "1.0.0";
            homepage = "https://oxc.rs";
          };
          source.type = "builtin";
          features = {
            files = true;
            scripts = true;
            healthchecks = true;
            packages = true;
          };
          tags = [
            "linting"
            "javascript"
            "typescript"
            "oxc"
            "rust"
          ];
          priority = 50;
          healthcheckModule = "oxlint";
        };
      }
    )
  ];
}
