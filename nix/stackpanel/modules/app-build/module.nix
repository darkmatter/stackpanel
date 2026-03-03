# ==============================================================================
# module.nix - App Build Module Implementation
#
# Provides per-app `build.*` options (serializable for UI) and Nix-only
# `package`/`checkPackage` options. Collects packages from language modules
# and routes them to flake outputs.
#
# Three responsibilities:
#   1. Register `build.*` appModule options (serializable scalars from schema)
#   2. Register `package`/`checkPackage` appModule options (Nix-only derivations)
#   3. Collect packages from language modules and manual overrides, route to
#      flake outputs/checks/apps
#
# Package collection priority (highest wins):
#   1. Manual app.package set by user in stackpanel.apps.<name>.package
#   2. Language module packages (stackpanel.go.packages.apps, stackpanel.bun.packages.apps)
#   3. commands.build.package from app-commands module
#
# NOTE: Language modules cannot write to stackpanel.apps (infinite recursion).
# Instead, they expose packages via their own options (e.g., stackpanel.go.packages.apps)
# and this module collects from those.
#
# Usage:
#   # Language modules expose packages via their own options:
#   stackpanel.go.packages.apps.<name> = <derivation>;
#   stackpanel.bun.packages.apps.<name> = <derivation>;
#
#   # Users can manually set package on an app:
#   stackpanel.apps.my-app.package = myCustomDrv;
#
#   # This module routes to:
#   stackpanel.outputs.<name> = <package>;
#   stackpanel.flakeApps.<name> = { type = "app"; program = ...; };
#   stackpanel.checks.<name>-test = <checkPackage>;
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

  # Unified field definitions - single source of truth for build per-app options
  buildSchema = import ./schema.nix { inherit lib; };
  sp = import ../../db/lib/field.nix { inherit lib; };

  # ---------------------------------------------------------------------------
  # Package collection from all sources
  # ---------------------------------------------------------------------------

  # Language module packages (no recursion - these are separate option trees)
  goPackages = cfg.go.packages.apps or {};
  bunPackages = cfg.bun.packages.apps or {};

  # Go test packages
  goTests = cfg.go.packages.tests or {};

  # Manual app.package overrides (reads cfg.apps but does NOT write to it)
  manualPackages = lib.filterAttrs (_: pkg: pkg != null)
    (lib.mapAttrs (_: app: app.package or null) cfg.apps);

  # Manual app.checkPackage overrides
  manualChecks = lib.filterAttrs (_: pkg: pkg != null)
    (lib.mapAttrs (_: app: app.checkPackage or null) cfg.apps);

  # Commands bridge: commands.build.package from app-commands module
  commandsPackages = lib.filterAttrs (_: pkg: pkg != null)
    (lib.mapAttrs (_: app:
      let cmds = app.commands or null; in
      if cmds != null &&
         cmds.build or null != null &&
         cmds.build.package or null != null
      then cmds.build.package
      else null
    ) cfg.apps);

  # Merge all package sources (manual > language > commands)
  # Later entries in // override earlier ones, so put highest priority last
  allPackages = commandsPackages // bunPackages // goPackages // manualPackages;
  allChecks = goTests // manualChecks;

  hasPackages = allPackages != {};
in
{
  # ===========================================================================
  # Configuration
  # ===========================================================================
  config = lib.mkMerge [
    # Always add build + package options to all apps (unconditional)
    {
      stackpanel.appModules = [
        (
          { lib, ... }:
          {
            # Serializable build options (from schema - visible to UI)
            options.build = lib.mkOption {
              type = lib.types.submodule {
                options = lib.mapAttrs (_: sp.asOption) buildSchema.fields;
              };
              default = { };
              description = "Build configuration for Nix packaging";
            };

            # Nix-only: built derivation (set by user or read from language modules)
            options.package = lib.mkOption {
              type = lib.types.nullOr lib.types.package;
              default = null;
              description = "Built derivation for this app (Nix-only, set by language modules)";
            };

            # Nix-only: test derivation (set by user or read from language modules)
            options.checkPackage = lib.mkOption {
              type = lib.types.nullOr lib.types.package;
              default = null;
              description = "Test derivation for this app (Nix-only)";
            };
          }
        )
      ];
    }

    # Route collected packages to flake outputs
    (lib.mkIf hasPackages {
      # Route to packages output (nix build .#<name>)
      stackpanel.outputs = allPackages;

      # Route to checks output (nix flake check)
      stackpanel.checks = lib.mapAttrs' (name: drv:
        lib.nameValuePair "${name}-test" drv
      ) allChecks;

      # Route to flake apps (nix run .#<name>)
      stackpanel.flakeApps = lib.mapAttrs (name: drv: {
        type = "app";
        program = lib.getExe drv;
      }) allPackages;

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
    })
  ];
}
