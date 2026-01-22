# ==============================================================================
# devenv-services.nix
#
# Bidirectional mapping for devenv services.
#
# READ PATH:  devenvSchema.services → stackpanel.devenvServices.available
#             (Exposes available services to UI)
#
# WRITE PATH: stackpanel.devenvServices.enabled → config.services.*.enable
#             (Applies user selections to devenv config)
#
# Usage in .stackpanel/config.nix:
#   stackpanel.devenvServices.enabled = [ "postgres" "redis" ];
#   stackpanel.devenvServices.config.postgres.port = 5433;
#
# The 'available' option is auto-populated from devenv and serialized to
# state.json for the UI to render a list of toggleable services.
# ==============================================================================
{
  config,
  lib,
  devenvSchema ? {
    services = {
      items = [ ];
    };
  },
  ...
}:
let
  cfg = config.stackpanel.devenvServices;
  spCfg = config.stackpanel;

  # READ: Available services from devenv schema
  availableServices = devenvSchema.services.items or [ ];
  availableIds = map (s: s.id) availableServices;

in
{
  # ===========================================================================
  # OPTIONS (what UI sees)
  # ===========================================================================
  options.stackpanel.devenvServices = {
    enable = lib.mkEnableOption "devenv services integration";

    # READ: What's available (derived from devenv, read-only)
    available = lib.mkOption {
      type = lib.types.listOf (lib.types.attrsOf lib.types.anything);
      default = availableServices;
      readOnly = true;
      description = ''
        Available devenv services. Auto-populated from devenv's options.
        Each service has: id, name, description, hasPort, hasPackage, hasSettings.
      '';
    };

    # WRITE: What user has enabled (from db/config)
    enabled = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        List of enabled service IDs (e.g., ["postgres" "redis"]).
        These must be valid service names from devenv.
      '';
    };

    # WRITE: Per-service configuration overrides
    config = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      example = {
        postgres.port = 5433;
        redis.port = 6380;
      };
      description = ''
        Per-service configuration overrides.
        Keys are service names, values are attrsets of options.
      '';
    };
  };

  # ===========================================================================
  # CONFIG (apply to devenv)
  # ===========================================================================
  config = lib.mkIf (cfg.enable && spCfg.enable) {
    # Validate enabled services exist
    assertions = [
      {
        assertion = lib.all (id: lib.elem id availableIds) cfg.enabled;
        message =
          let
            invalid = lib.filter (id: !(lib.elem id availableIds)) cfg.enabled;
          in
          "Unknown devenv services: ${lib.concatStringsSep ", " invalid}. "
          + "Available: ${lib.concatStringsSep ", " availableIds}";
      }
    ];

    # Map enabled services to devenv config
    # This sets config.services.<name>.enable = true for each enabled service
    services = lib.genAttrs cfg.enabled (
      name:
      {
        enable = true;
      }
      // (cfg.config.${name} or { })
    );

    # Serialize to state for UI access
    stackpanel.state.devenv.services = {
      available = cfg.available;
      enabled = cfg.enabled;
    };
  };
}
