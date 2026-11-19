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
#   2. A runtime build provider in stackpanel.appBuildProviders.<runtime>.<name>
#   3. commands.build.package from app-commands module
#
# Runtime modules publish derivations outside apps to avoid recursing through
# the app submodule while it is being evaluated.
#
# Usage:
#   stackpanel.appBuildProviders.rust.<name> = <derivation>;
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
  ...
}:
let
  meta = import ./meta.nix;
  cfg = config.stackpanel;

  # Unified field definitions - single source of truth for build per-app options
  buildSchema = import ./schema.nix { inherit lib; };
  sp = lib.stackpanel.spField;

  # ---------------------------------------------------------------------------
  # Package collection from all sources
  # ---------------------------------------------------------------------------

  # Manual app.package overrides (reads cfg.apps but does NOT write to it)
  manualPackages = lib.filterAttrs (_: pkg: pkg != null) (
    lib.mapAttrs (_: app: app.package or null) cfg.apps
  );

  # Manual app.checkPackage overrides
  manualChecks = lib.filterAttrs (_: pkg: pkg != null) (
    lib.mapAttrs (_: app: app.checkPackage or null) cfg.apps
  );

  # Commands bridge: commands.build.package from app-commands module
  commandsPackages = lib.filterAttrs (_: pkg: pkg != null) (
    lib.mapAttrs (
      _: app:
      let
        cmds = app.commands or null;
      in
      if cmds != null && (cmds.build.enable or false) && (cmds.build.package or null) != null then
        cmds.build.package
      else
        null
    ) cfg.apps
  );

  # Merge all package sources (manual > language > commands)
  # Later entries in // override earlier ones, so put highest priority last
  allPackages = commandsPackages // cfg.appBuildPackages // manualPackages;

  hasPackages = allPackages != { } || manualChecks != { };
in
{
  # ===========================================================================
  # Configuration
  # ===========================================================================
  config = lib.mkMerge [
    # Always add build + package options to all apps (unconditional)
    {
      stackpanel.modules.${meta.id} = {
        enable = lib.mkDefault hasPackages;
        meta = {
          inherit (meta)
            name
            description
            icon
            category
            author
            version
            homepage
            ;
        };
        source.type = "builtin";
        inherit (meta) features tags priority;
      };

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
              description = ''
                Serializable build configuration for Nix packaging.

                These fields describe source layout, lockfiles, and output names.
                Language modules read them when constructing actual derivations.
              '';
            };

            # Nix-only: built derivation (set by user or read from language modules)
            options.package = lib.mkOption {
              type = lib.types.nullOr lib.types.package;
              default = null;
              description = ''
                Built derivation for this app.

                This Nix-only option may be set manually, or supplied indirectly by
                language modules such as Go and Bun. When present, app-build routes it
                to flake packages/apps.
              '';
              example = lib.literalExpression "pkgs.hello";
            };

            # Nix-only: test derivation (set by user or read from language modules)
            options.checkPackage = lib.mkOption {
              type = lib.types.nullOr lib.types.package;
              default = null;
              description = ''
                Test/check derivation for this app.

                When set, app-build exposes it as a flake check named
                `<app>-test`, so it runs during `nix flake check`.
              '';
              example = lib.literalExpression ''
                pkgs.runCommand "web-test" { } "touch $out"
              '';
            };
          }
        )
      ];
    }

    # Route collected packages to flake outputs
    (lib.mkIf (cfg.modules.${meta.id}.enable && hasPackages) {
      # Route to packages output (nix build .#<name>)
      stackpanel.outputs = allPackages;

      # Route to checks output (nix flake check)
      stackpanel.checks = lib.mapAttrs' (name: drv: lib.nameValuePair "${name}-test" drv) manualChecks;

      # Route to flake apps (nix run .#<name>)
      stackpanel.flakeApps = lib.mapAttrs (
        _name: drv:
        lib.mkDefault {
          type = "app";
          program = lib.getExe drv;
        }
      ) allPackages;
    })
  ];
}
