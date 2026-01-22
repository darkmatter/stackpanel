# ==============================================================================
# devenv-languages.nix
#
# Bidirectional mapping for devenv languages.
#
# READ PATH:  devenvSchema.languages → stackpanel.devenvLanguages.available
#             (Exposes available languages to UI)
#
# WRITE PATH: stackpanel.devenvLanguages.enabled → config.languages.*.enable
#             (Applies user selections to devenv config)
#
# Usage in .stackpanel/config.nix:
#   stackpanel.devenvLanguages.enabled = [ "javascript" "typescript" "go" ];
#   stackpanel.devenvLanguages.config.go.version = "1.21";
#
# The 'available' option is auto-populated from devenv and serialized to
# state.json for the UI to render a list of toggleable languages.
# ==============================================================================
{
  config,
  lib,
  devenvSchema ? {
    languages = {
      items = [ ];
    };
  },
  ...
}:
let
  cfg = config.stackpanel.devenvLanguages;
  spCfg = config.stackpanel;

  # READ: Available languages from devenv schema
  availableLanguages = devenvSchema.languages.items or [ ];
  availableIds = map (l: l.id) availableLanguages;

in
{
  # ===========================================================================
  # OPTIONS (what UI sees)
  # ===========================================================================
  options.stackpanel.devenvLanguages = {
    enable = lib.mkEnableOption "devenv languages integration";

    # READ: What's available (derived from devenv, read-only)
    available = lib.mkOption {
      type = lib.types.listOf (lib.types.attrsOf lib.types.anything);
      default = availableLanguages;
      readOnly = true;
      description = ''
        Available devenv languages. Auto-populated from devenv's options.
        Each language has: id, name, description, hasVersion, hasPackage.
      '';
    };

    # WRITE: What user has enabled (from db/config)
    enabled = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        List of enabled language IDs (e.g., ["javascript" "typescript" "go"]).
        These must be valid language names from devenv.
      '';
    };

    # WRITE: Per-language configuration overrides
    config = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      example = {
        go.version = "1.21";
        python.version = "3.11";
      };
      description = ''
        Per-language configuration overrides.
        Keys are language names, values are attrsets of options.
      '';
    };
  };

  # ===========================================================================
  # CONFIG (apply to devenv)
  # ===========================================================================
  config = lib.mkIf (cfg.enable && spCfg.enable) {
    # Validate enabled languages exist
    assertions = [
      {
        assertion = lib.all (id: lib.elem id availableIds) cfg.enabled;
        message =
          let
            invalid = lib.filter (id: !(lib.elem id availableIds)) cfg.enabled;
          in
          "Unknown devenv languages: ${lib.concatStringsSep ", " invalid}. "
          + "Available: ${lib.concatStringsSep ", " availableIds}";
      }
    ];

    # Map enabled languages to devenv config
    languages = lib.genAttrs cfg.enabled (
      name:
      {
        enable = true;
      }
      // (cfg.config.${name} or { })
    );

    # Serialize to state for UI access
    stackpanel.state.devenv.languages = {
      available = cfg.available;
      enabled = cfg.enabled;
    };
  };
}
