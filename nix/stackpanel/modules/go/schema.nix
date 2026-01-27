# ==============================================================================
# go-app.proto.nix
#
# Unified field definitions for Go app configuration.
#
# This is the SINGLE SOURCE OF TRUTH for Go module per-app options.
# It defines SpFields that simultaneously serve as:
#   1. Proto fields → GoAppConfig message (for Go/TS codegen)
#   2. Nix option source → go/module.nix uses asOption to create lib.mkOption
#   3. UI panel source → go/ui.nix uses fields for auto-generated panels
#
# Usage from module.nix:
#   let goSchema = import ./schema.nix { inherit lib; };
#   in { options.go.mainPackage = sp.asOption goSchema.fields.mainPackage; }
#
# Usage from ui.nix:
#   let goSchema = import ./schema.nix { inherit lib; };
#   in panelsLib.mkPanelFromSpFields { fields = goSchema.fields; ... }
#
# Proto generation:
#   goSchema.protoFile → rendered .proto file with GoAppConfig message
# ==============================================================================
{ lib }:
let
  sp = import ../../db/lib/field.nix { inherit lib; };
  proto = import ../../db/lib/proto.nix { inherit lib; };

  # ===========================================================================
  # Field definitions (camelCase keys - zero conversion to Nix/JSON/Go/TS)
  # ===========================================================================
  fields = {
    # Whether this app uses Go (hidden from UI - set by module config)
    enable = sp.bool {
      index = 1;
      description = "Enable Go app support for this app";
      default = false;
      ui = null; # Hidden: controlled by module, not user-editable in panels
    };

    # Go main package path (e.g., "." or "./cmd/server")
    mainPackage = sp.string {
      index = 2;
      description = "Go main package path";
      default = ".";
      example = "./cmd/server";
      ui = {
        label = "Main Package";
        placeholder = "./cmd/server";
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
      ui = {
        label = "Binary Name";
        placeholder = "my-binary";
      };
    };

    # Go linker flags
    ldflags = sp.string {
      index = 5;
      repeated = true;
      description = "Go linker flags";
      default = [ ];
      example = [ "-X main.version=1.0.0" ];
      ui = {
        label = "Linker Flags";
      };
    };

    # Directories to watch for air live reload
    watchDirs = sp.string {
      index = 6;
      repeated = true;
      description = "Directories to watch for air live reload";
      default = [
        "cmd"
        "internal"
      ];
      ui = {
        label = "Watch Directories";
      };
    };

    # Arguments to pass to binary during development
    devArgs = sp.string {
      index = 7;
      repeated = true;
      description = "Arguments to pass to binary during development";
      default = [ ];
      example = [
        "serve"
        "--port=3000"
      ];
      ui = {
        label = "Dev Arguments";
      };
    };

    # Additional Go tool dependencies (hidden - too internal for panel)
    tools = sp.string {
      index = 8;
      repeated = true;
      description = "Additional Go tool dependencies";
      default = [ ];
      example = [ "github.com/golangci/golangci-lint/cmd/golangci-lint" ];
      ui = null; # Hidden: Go import paths aren't meaningful in a UI form
    };

    # Whether to generate package.json, .air.toml, and tools.go
    generateFiles = sp.bool {
      index = 9;
      description = "Generate package.json, .air.toml, and tools.go";
      default = true;
      ui = {
        label = "Generate Files";
      };
    };

    # App description
    description = sp.string {
      index = 10;
      description = "App description";
      default = "";
      ui = {
        label = "Description";
        placeholder = "A Go application";
      };
    };
  };

in
# Return the proto file object directly (generate.sh expects schema.name),
# with fields merged in (module.nix / ui.nix use schema.fields).
proto.mkProtoFile {
  name = "go_app.proto";
  package = "stackpanel.modules";

  options = {
    go_package = "github.com/darkmatter/stackpanel/packages/proto/gen/gopb";
  };

  messages = {
    GoAppConfig = proto.mkMessage {
      name = "GoAppConfig";
      description = "Go-specific per-app configuration";
      fields = sp.toProtoFields fields;
    };
  };
}
// { inherit fields; }
