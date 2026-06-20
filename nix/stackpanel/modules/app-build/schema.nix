# ==============================================================================
# app-build.proto.nix
#
# Unified field definitions for app build configuration.
#
# This is the SINGLE SOURCE OF TRUTH for app-build module per-app options.
# It defines SpFields that simultaneously serve as:
#   1. Proto fields -> AppBuildConfig message (for Go/TS codegen)
#   2. Nix option source -> app-build/module.nix uses asOption to create lib.mkOption
#   3. UI panel source -> app-build/ui.nix uses fields for auto-generated panels
#
# These are serializable scalars only -- no derivations. Language modules
# read these fields and compute the actual derivations (app.package).
#
# Usage from module.nix:
#   let buildSchema = import ./schema.nix { inherit lib; };
#   in { options.build = lib.mapAttrs (_: sp.asOption) buildSchema.fields; }
#
# Proto generation:
#   buildSchema.protoFile -> rendered .proto file with AppBuildConfig message
# ==============================================================================
{ lib }:
let
  sp = import ../../db/lib/field.nix { inherit lib; };
  proto = import ../../db/lib/proto.nix { inherit lib; };

  # ===========================================================================
  # Field definitions (camelCase keys - zero conversion to Nix/JSON/Go/TS)
  # ===========================================================================
  fields = {
    # Whether build packaging is enabled (hidden - auto-set by language modules)
    enable = sp.bool {
      index = 1;
      description = ''
        Enable Nix packaging for this app.

        Language modules usually set this automatically when they can produce a
        package. Manual apps can enable it when supplying `apps.<name>.package`.
      '';
      default = false;
      ui = null; # Hidden: auto-set by language modules, not user-editable
    };

    # Source root relative to repo (null = auto-detect from layout)
    srcRoot = sp.string {
      index = 2;
      description = ''
        Source root relative to repository root.

        Use to override auto-detection for unusual layouts, e.g. `apps/web` or
        `services/api`.
      '';
      optional = true;
      ui = {
        label = "Source Root";
        placeholder = "apps/my-app";
      };
    };

    # Source layout: workspace or standalone (null = auto-detect)
    srcLayout = sp.string {
      index = 3;
      description = ''
        Source layout hint for package builders.

        Use `workspace` for monorepo packages sharing root lockfiles, or
        `standalone` when the app owns its lockfile and dependency graph.
      '';
      optional = true;
      ui = {
        label = "Source Layout";
        placeholder = "workspace";
      };
    };

    # Glob patterns for source filter
    srcInclude = sp.string {
      index = 4;
      repeated = true;
      description = ''
        Glob patterns included in source filtering for package builds.

        Keep narrow to avoid unnecessary rebuilds; include source files, package
        manifests, lockfiles, and config needed by the build.
      '';
      default = [ ];
      example = [
        "src/**"
        "package.json"
      ];
      ui = {
        label = "Source Include Patterns";
      };
    };

    # Lockfile path relative to repo (null = auto-detect)
    depsLockfile = sp.string {
      index = 5;
      description = ''
        Dependency lockfile path relative to repository root.

        Use when auto-detection picks the wrong lockfile, e.g. `bun.lock`,
        `pnpm-lock.yaml`, or `gomod2nix.toml`.
      '';
      optional = true;
      ui = {
        label = "Deps Lockfile";
        placeholder = "gomod2nix.toml";
      };
    };

    # Override output package name (null = use app name)
    outputName = sp.string {
      index = 6;
      description = ''
        Optional package output name override.

        Defaults to the app key. Set when the flake package should be named after
        a binary or published artifact instead.
      '';
      optional = true;
      ui = {
        label = "Output Name";
        placeholder = "my-package";
      };
    };

    # Package version
    outputVersion = sp.string {
      index = 7;
      description = ''
        Package version for generated derivation metadata.

        Keep aligned with app release versions when packages are published or
        deployed outside the devshell.
      '';
      default = "0.1.0";
      ui = {
        label = "Version";
        placeholder = "0.1.0";
      };
    };
  };

in
# Return the proto file object directly (generate.sh expects schema.name),
# with fields merged in (module.nix / ui.nix use schema.fields).
proto.mkProtoFile {
  name = "app_build.proto";
  package = "stackpanel.modules";

  options = {
    go_package = "github.com/darkmatter/stackpanel/packages/proto/gen/gopb";
  };

  messages = {
    AppBuildConfig = proto.mkMessage {
      name = "AppBuildConfig";
      description = "Build configuration for Nix packaging";
      fields = sp.toProtoFields fields;
    };
  };
}
// {
  inherit fields;
}
