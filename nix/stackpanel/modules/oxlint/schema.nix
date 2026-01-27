# ==============================================================================
# oxlint-app.proto.nix
#
# Unified field definitions for OxLint per-app configuration.
#
# This is the SINGLE SOURCE OF TRUTH for OxLint module per-app options.
# It defines SpFields that simultaneously serve as:
#   1. Proto fields → OxlintAppConfig message (for Go/TS codegen)
#   2. Nix option source → oxlint/module.nix uses asOption to create lib.mkOption
#   3. UI panel source → oxlint/ui.nix uses fields for auto-generated panels
#
# NOTE: The `package` option is Nix-only (listOf package has no proto equivalent)
# and remains as a manual lib.mkOption in module.nix.
#
# Usage from module.nix:
#   let oxlintSchema = import ./schema.nix { inherit lib; };
#   in { options = lib.mapAttrs (_: sp.asOption) oxlintSchema.fields; }
#
# Usage from ui.nix:
#   let oxlintSchema = import ./schema.nix { inherit lib; };
#   in panelsLib.mkPanelFromSpFields { fields = oxlintSchema.fields; ... }
# ==============================================================================
{lib}: let
  sp = import ../../db/lib/field.nix {inherit lib;};
  proto = import ../../db/lib/proto.nix {inherit lib;};

  # ===========================================================================
  # Field definitions (camelCase keys - zero conversion to Nix/JSON/Go/TS)
  # ===========================================================================
  fields = {
    # Whether this app uses OxLint (hidden from UI - set by module config)
    enable = sp.bool {
      index = 1;
      description = "Enable OxLint for JavaScript/TypeScript linting";
      default = false;
      ui = null; # Hidden: controlled by module, not user-editable in panels
    };

    # Custom config file path (relative to app root)
    configPath = sp.string {
      index = 2;
      description = "Path to oxlint config file relative to app root";
      optional = true;
      example = "oxlint.json";
      ui = {
        label = "Config Path";
        placeholder = ".oxlintrc.json";
      };
    };

    # OxLint plugins to enable
    plugins = sp.string {
      index = 3;
      repeated = true;
      description = "OxLint plugins to enable";
      default = [];
      example = [
        "react"
        "typescript"
        "import"
        "jsx-a11y"
      ];
      ui = {
        label = "Plugins";
      };
    };

    # Rule category severity levels
    categories = sp.string {
      index = 4;
      mapKey = "string";
      description = "Rule category severity levels";
      default = {
        correctness = "error";
        suspicious = "warn";
        pedantic = "off";
        style = "off";
        nursery = "off";
      };
      ui = {
        type = sp.uiType.code;
        label = "Categories";
      };
    };

    # Individual rule overrides
    rules = sp.string {
      index = 5;
      mapKey = "string";
      description = "Individual rule overrides. Values: off, warn, error";
      default = {};
      example = {
        "no-console" = "warn";
        "no-debugger" = "error";
        "eqeqeq" = "error";
      };
      ui = {
        label = "Rules";
      };
    };

    # Glob patterns to ignore
    ignorePatterns = sp.string {
      index = 6;
      repeated = true;
      description = "Glob patterns to ignore";
      default = [
        "node_modules"
        "dist"
        "build"
        ".next"
        "coverage"
        "*.min.js"
        "*.bundle.js"
      ];
      ui = {
        label = "Ignore Patterns";
      };
    };

    # Paths to lint (relative to app root)
    paths = sp.string {
      index = 7;
      repeated = true;
      description = "Paths to lint (relative to app root)";
      default = [
        "src"
        "."
      ];
      ui = {
        label = "Paths";
      };
    };

    # Auto-fix fixable issues
    fix = sp.bool {
      index = 8;
      description = "Whether to automatically fix fixable issues by default";
      default = false;
      ui = {
        label = "Auto Fix";
      };
    };

    # Git hook integration
    gitHook = sp.bool {
      index = 9;
      description = "Whether to run oxlint in pre-commit git hook";
      default = true;
      ui = {
        label = "Git Hook";
      };
    };

    # Deprecated turbo task option (hidden)
    turboTask = sp.bool {
      index = 10;
      description = "Deprecated: This option is no longer used";
      default = false;
      ui = null; # Hidden: deprecated
    };
  };
in
  # Return the proto file object directly (generate.sh expects schema.name),
  # with fields merged in (module.nix / ui.nix use schema.fields).
  proto.mkProtoFile {
    name = "oxlint_app.proto";
    package = "stackpanel.modules";

    options = {
      go_package = "github.com/darkmatter/stackpanel/packages/proto/gen/gopb";
    };

    messages = {
      OxlintAppConfig = proto.mkMessage {
        name = "OxlintAppConfig";
        description = "OxLint per-app linting configuration";
        fields = sp.toProtoFields fields;
      };
    };
  }
  // {inherit fields;}
