# ==============================================================================
# devenv-pre-commit.nix
#
# Bidirectional mapping for devenv pre-commit hooks.
#
# READ PATH:  devenvSchema.preCommit.hooks → stackpanel.devenvPreCommit.available
#             (Exposes available hooks to UI)
#
# WRITE PATH: stackpanel.devenvPreCommit.enabled → config.pre-commit.hooks.*.enable
#             (Applies user selections to devenv config)
#
# Usage in .stackpanel/config.nix:
#   stackpanel.devenvPreCommit.enabled = [ "prettier" "eslint" "nixfmt" ];
#
# The 'available' option shows only built-in hooks (those with default entries).
# Custom hooks require manual configuration in devenv.nix.
# ==============================================================================
{
  config,
  lib,
  devenvSchema ? {
    preCommit = {
      hooks = [ ];
    };
  },
  ...
}:
let
  cfg = config.stackpanel.devenvPreCommit;
  spCfg = config.stackpanel;

  # READ: Available hooks from devenv schema
  allHooks = devenvSchema.preCommit.hooks or [ ];

  # Only expose built-in hooks (ones that don't need custom entry)
  # Custom hooks require the user to define 'entry', so they can't be toggled
  builtinHooks = lib.filter (h: h.isBuiltin or false) allHooks;
  availableIds = map (h: h.id) builtinHooks;

in
{
  # ===========================================================================
  # OPTIONS (what UI sees)
  # ===========================================================================
  options.stackpanel.devenvPreCommit = {
    enable = lib.mkEnableOption "devenv pre-commit hooks integration";

    # READ: Available hooks (derived from devenv, read-only)
    available = lib.mkOption {
      type = lib.types.listOf (lib.types.attrsOf lib.types.anything);
      default = builtinHooks;
      readOnly = true;
      description = ''
        Available pre-commit hooks from devenv. Only includes built-in hooks
        that have default entries (can be enabled without custom configuration).
        Each hook has: id, name, description, isBuiltin.
      '';
    };

    # READ: All hooks including custom (for reference)
    allAvailable = lib.mkOption {
      type = lib.types.listOf (lib.types.attrsOf lib.types.anything);
      default = allHooks;
      readOnly = true;
      description = ''
        All available pre-commit hooks from devenv, including custom hooks
        that require manual 'entry' configuration.
      '';
    };

    # WRITE: What user has enabled (from db/config)
    enabled = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        List of enabled hook IDs (e.g., ["prettier" "eslint" "nixfmt"]).
        These must be built-in hooks from devenv.
      '';
    };

    # WRITE: Per-hook configuration overrides
    config = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      example = {
        prettier.excludes = [ "*.min.js" ];
        eslint.files = "\\.tsx?$";
      };
      description = ''
        Per-hook configuration overrides.
        Keys are hook names, values are attrsets of options (files, excludes, etc.).
      '';
    };
  };

  # ===========================================================================
  # CONFIG (apply to devenv)
  # ===========================================================================
  config = lib.mkIf (cfg.enable && spCfg.enable) {
    # Validate enabled hooks exist and are built-in
    assertions = [
      {
        assertion = lib.all (id: lib.elem id availableIds) cfg.enabled;
        message =
          let
            invalid = lib.filter (id: !(lib.elem id availableIds)) cfg.enabled;
          in
          "Unknown or non-built-in pre-commit hooks: ${lib.concatStringsSep ", " invalid}. "
          + "Available built-in hooks: ${lib.concatStringsSep ", " availableIds}";
      }
    ];

    # Map enabled hooks to devenv config
    pre-commit.hooks = lib.genAttrs cfg.enabled (
      name:
      {
        enable = true;
      }
      // (cfg.config.${name} or { })
    );

    # Serialize to state for UI access
    stackpanel.state.devenv.preCommit = {
      available = cfg.available;
      enabled = cfg.enabled;
    };
  };
}
