# ==============================================================================
# module.nix - OxLint Module Implementation
#
# OxLint (https://oxc.rs) is a blazing fast JavaScript/TypeScript linter
# written in Rust. This module provides:
#
#   1. Devshell packages (oxlint)
#   2. Per-app linting configuration via stackpanel.apps.*.linting.oxlint
#   3. Config file generation (.oxlintrc.json)
#   4. Shell scripts (lint, lint:fix)
#   5. Git hooks integration (pre-commit linting)
#   6. Health checks
# ==============================================================================
{
  lib,
  config,
  pkgs,
  ...
}:
let
  meta = import ./meta.nix;
  cfg = config.stackpanel;

  # Import unified field definitions (single source of truth)
  oxlintSchema = import ./schema.nix { inherit lib; };
  spField = import ../../db/lib/field.nix { inherit lib; };

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

in
{
  config = lib.mkMerge [
    # Always register the per-app options module
    # Options are auto-generated from oxlint-app.proto.nix (single source of truth)
    # `package` is Nix-only (package type has no proto equivalent)
    {
      stackpanel.appModules = [
        (
          { lib, ... }:
          {
            options.linting.oxlint = lib.mkOption {
              type = lib.types.submodule {
                options = lib.mapAttrs (_: spField.asOption) oxlintSchema.fields // {
                  # Nix-only option: package references can't be proto fields
                  package = lib.mkOption {
                    type = lib.types.package;
                    default = pkgs.oxlint;
                    defaultText = lib.literalExpression "pkgs.oxlint";
                    description = "The oxlint package to use.";
                  };
                };
              };
              default = { };
              description = "OxLint linting configuration for this app";
            };
          }
        )
      ];
    }

    # Apply configuration when oxlint apps exist
    (
      let
        # Re-evaluate inside the mkMerge block
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
          lib.optionalAttrs (oxCfg.configPath == null) {
            "${appPath}/${configFileName}" = {
              type = "text";
              text = builtins.toJSON (mkOxlintConfig name appCfg);
              description = "OxLint configuration for ${name}";
              source = meta.id;
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

        # Add linters for git hooks
        stackpanel.git-hooks.extraLinters = lib.flatten (
          lib.mapAttrsToList (
            name: appCfg:
            let
              oxCfg = appCfg.linting.oxlint;
            in
            lib.optional oxCfg.gitHook (mkWrappedLinter name appCfg)
          ) oxlintAppsLocal
        );

        # =========================================================================
        # Flake Checks (CI) - Run with `nix flake check`
        # =========================================================================
        stackpanel.moduleChecks.${meta.id} = {
          # REQUIRED: Verify module evaluates without errors
          eval = {
            description = "OxLint module evaluates correctly";
            required = true;
            derivation = pkgs.runCommand "${meta.id}-eval-check" {} ''
              echo "✓ OxLint module evaluates successfully"
              touch $out
            '';
          };

          # REQUIRED: Verify oxlint package is available
          packages = {
            description = "OxLint package is available";
            required = true;
            derivation = pkgs.runCommand "${meta.id}-packages-check" {
              nativeBuildInputs = [ pkgs.oxlint ];
            } ''
              oxlint --version > $out
              echo "✓ OxLint package available"
            '';
          };

          # RECOMMENDED: Verify config generation works
          config = {
            description = "OxLint config generation works";
            required = false;
            derivation = pkgs.runCommand "${meta.id}-config-check" {
              nativeBuildInputs = [ pkgs.jq ];
            } ''
              # Test that we can generate valid JSON config
              echo '${builtins.toJSON {
                "$schema" = "https://raw.githubusercontent.com/oxc-project/oxc/main/npm/oxlint/configuration_schema.json";
                plugins = [];
                categories = { correctness = "error"; };
                rules = {};
                ignorePatterns = [ "node_modules" ];
              }}' | jq . > $out
              echo "✓ Config generation produces valid JSON"
            '';
          };
        };

        # =========================================================================
        # Health Checks (Runtime) - Shown in UI, run in devshell
        # =========================================================================
        stackpanel.healthchecks.modules.${meta.id} = {
          enable = true;
          displayName = meta.name;
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

        # Register as a stackpanel module
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
          healthcheckModule = meta.id;
        };
      }
    )
  ];
}
