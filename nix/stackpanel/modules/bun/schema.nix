# ==============================================================================
# bun-app.proto.nix
#
# Unified field definitions for Bun app configuration.
#
# This is the SINGLE SOURCE OF TRUTH for Bun module per-app options.
# It defines SpFields that simultaneously serve as:
#   1. Proto fields → BunAppConfig message (for Go/TS codegen)
#   2. Nix option source → bun/module.nix uses asOption to create lib.mkOption
#   3. UI panel source → bun/ui.nix uses fields for auto-generated panels
#
# NOTE: Some Bun options (runtimeInputs) are Nix-only and cannot be
# represented as SpFields. These remain as manual lib.mkOption definitions
# in module.nix alongside the auto-generated ones.
#
# Usage from module.nix:
#   let bunSchema = import ./schema.nix { inherit lib; };
#   in { options = lib.mapAttrs (_: sp.asOption) bunSchema.fields; }
#
# Usage from ui.nix:
#   let bunSchema = import ./schema.nix { inherit lib; };
#   in panelsLib.mkPanelFromSpFields { fields = bunSchema.fields; ... }
#
# Proto generation:
#   bunSchema.protoFile → rendered .proto file with BunAppConfig message
# ==============================================================================
{ lib }:
let
  sp = import ../../db/lib/field.nix { inherit lib; };
  proto = import ../../db/lib/proto.nix { inherit lib; };

  # ===========================================================================
  # Field definitions (camelCase keys - zero conversion to Nix/JSON/Go/TS)
  # ===========================================================================
  fields = {
    # Whether this app uses Bun (hidden from UI - set by module config)
    enable = sp.bool {
      index = 1;
      description = "Enable Bun app support for this app";
      default = false;
      ui = null; # Hidden: controlled by module, not user-editable in panels
    };

    # Bun main entry point (e.g., "." or "src/index.ts")
    mainPackage = sp.string {
      index = 2;
      description = "Main entry point for bun run";
      default = ".";
      example = "src/index.ts";
      ui = {
        label = "Main Package";
        placeholder = "src/index.ts";
      };
    };

    # App version for build metadata
    version = sp.string {
      index = 3;
      description = "App version";
      default = "0.1.0";
      ui = {
        label = "Version";
        placeholder = "0.1.0";
      };
    };

    # Binary name override (if different from app name)
    binaryName = sp.string {
      index = 4;
      description = "Binary name (if different from app name)";
      optional = true;
      example = "my-app";
      ui = {
        label = "Binary Name";
        placeholder = "my-app";
      };
    };

    # Build phase command
    buildPhase = sp.string {
      index = 5;
      description = "Build phase command";
      default = "bun run build";
      ui = {
        label = "Build Phase";
        placeholder = "bun run build";
      };
    };

    # Start script for runtime
    startScript = sp.string {
      index = 6;
      description = "Start script for runtime";
      default = "bun run start";
      ui = {
        label = "Start Script";
        placeholder = "bun run start";
      };
    };

    # Runtime environment variables (map<string, string>)
    runtimeEnv = sp.string {
      index = 7;
      mapKey = "string";
      description = "Runtime environment variables";
      default = { };
      example = {
        NODE_ENV = "production";
      };
      ui = {
        label = "Runtime Environment";
      };
    };

    # Whether to inherit PATH from environment at runtime
    inheritPath = sp.bool {
      index = 8;
      description = "Whether to inherit PATH from environment at runtime";
      default = false;
      ui = {
        label = "Inherit PATH";
      };
    };

    # App description
    description = sp.string {
      index = 9;
      description = "App description";
      default = "";
      ui = {
        label = "Description";
        placeholder = "A Bun/TypeScript application";
      };
    };
  };

in
# Return the proto file object directly (generate.sh expects schema.name),
# with fields merged in (module.nix / ui.nix use schema.fields).
proto.mkProtoFile {
  name = "bun_app.proto";
  package = "stackpanel.modules";

  options = {
    go_package = "github.com/darkmatter/stackpanel/packages/proto/gen/gopb";
  };

  messages = {
    BunAppConfig = proto.mkMessage {
      name = "BunAppConfig";
      description = "Bun-specific per-app configuration";
      fields = sp.toProtoFields fields;
    };
  };
}
// { inherit fields; }
