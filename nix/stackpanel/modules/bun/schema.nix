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
      description = ''
        Enable Bun app support for this app.

        When true, Stackpanel generates Bun package metadata, adds Bun tooling to
        the devshell, wires standard build/start scripts, and exposes the app's
        Nix package through stackpanel.bun.packages.apps.<name>.

        Example: `stackpanel.apps.web.bun.enable = true;`
      '';
      default = false;
      ui = null; # Hidden: controlled by module, not user-editable in panels
    };

    # Bun main entry point (e.g., "." or "src/index.ts")
    mainPackage = sp.string {
      index = 2;
      description = ''
        Main Bun entry point passed to generated package metadata.

        Use `.` for apps whose package.json owns scripts, or a source file such
        as `src/index.ts` for single-entry executables.
      '';
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
      description = ''
        Version string written to generated package.json and package metadata.

        Keep this aligned with release tags when the Bun app is distributed as a
        standalone package.
      '';
      default = "0.1.0";
      ui = {
        label = "Version";
        placeholder = "0.1.0";
      };
    };

    # Binary name override (if different from app name)
    binaryName = sp.string {
      index = 4;
      description = ''
        Optional runtime binary name when it differs from the Stackpanel app key.

        Example: app key `stackpanel-go`, binary name `stackpanel`.
      '';
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
      description = ''
        Command executed during the Bun package build phase.

        It runs from the app directory and should create outputDir. Typical
        values are `bun run build`, `bun run build:worker`, or `bunx vite build`.
      '';
      default = "bun run build";
      ui = {
        label = "Build Phase";
        placeholder = "bun run build";
      };
    };

    # Start script for runtime
    startScript = sp.string {
      index = 6;
      description = ''
        Runtime start command written to generated package.json.

        Use this for the production entrypoint, not the dev server. Examples:
        `bun run start`, `bun .output/server/index.mjs`, or `wrangler dev` for
        local-only wrappers.
      '';
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
      description = ''
        Environment variables baked into the generated runtime wrapper.

        Use for non-secret defaults such as NODE_ENV or feature flags. Put
        secrets in stackpanel env/secrets so they are materialized at runtime.
      '';
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
      description = ''
        Whether generated wrappers inherit the caller's PATH at runtime.

        Keep false for hermetic packages. Set true only when the app intentionally
        shells out to tools supplied by the deployment environment.
      '';
      default = false;
      ui = {
        label = "Inherit PATH";
      };
    };

    # Whether to generate package.json with bun2nix postinstall
    generateFiles = sp.bool {
      index = 9;
      description = ''
        Generate package.json with bun2nix postinstall and standard scripts.

        Leave enabled for managed Bun apps so `deps`, `build`, and `start` stay
        consistent. Disable only when a hand-written package.json must remain
        fully unmanaged.
      '';
      default = true;
      ui = {
        label = "Generate Files";
      };
    };

    # App description
    description = sp.string {
      index = 10;
      description = ''
        Human-readable app description written to generated package metadata and
        surfaced in Stackpanel UI panels.
      '';
      default = "";
      ui = {
        label = "Description";
        placeholder = "A Bun/TypeScript application";
      };
    };

    # Build output directory to install into the final package
    outputDir = sp.string {
      index = 11;
      description = ''
        Directory copied into the final packaged artifact after buildPhase.

        Examples: `.output` for TanStack/Workers builds, `dist` for Vite apps,
        or `build` for custom bundlers.
      '';
      default = ".output";
      example = "dist";
      ui = {
        label = "Output Directory";
        placeholder = ".output";
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
// {
  inherit fields;
}
