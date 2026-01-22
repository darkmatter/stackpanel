# ==============================================================================
# cfg.nix
#
# Unified config value resolution with defined precedence.
#
# Problem: Scripts hardcode defaults like ".stackpanel/state" in multiple places.
# If config overrides this path, scripts don't pick it up → drift and bugs.
#
# Solution: Single-identity variable resolution with precedence order:
#   1. Environment variable (STACKPANEL_<PATH>) - runtime override
#   2. CLI query (stackpanel config get <path>) - current config value
#   3. Default (baked from Nix config) - fallback
#
# Usage:
#   let cfg = import ./cfg.nix { inherit lib config; }; in
#   {
#     myScript = ''
#       ${cfg.bashLib}
#       
#       STATE_DIR=${cfg.get "paths.state"}
#       KEYS_DIR=${cfg.get "paths.keys"}
#     '';
#   }
#
# The bashLib provides the sp_get function. The getter returns $(sp_get ...).
# Each variable has ONE identity (the path) - resolution logic is centralized.
#
# ==============================================================================
{
  lib,
  config ? null,
}:
let
  # ===========================================================================
  # PATH UTILITIES
  # ===========================================================================

  # Convert a dot path to an env var name
  # "paths.state" → "STACKPANEL_PATHS_STATE"
  pathToEnvVar =
    path: "STACKPANEL_${lib.toUpper (builtins.replaceStrings [ "." ] [ "_" ] path)}";

  # Get default value from config by path
  # Returns empty string if config not available or path not found
  getDefault =
    path:
    if config == null then
      ""
    else
      let
        val = lib.attrByPath (lib.splitString "." path) null config.stackpanel;
      in
      if val == null then "" else toString val;

  # ===========================================================================
  # BASH LIBRARY
  #
  # This gets injected at the top of scripts. Provides sp_get function.
  # ===========================================================================

  bashLib = ''
    # ==========================================================================
    # sp_get - Resolve a config value with precedence
    #
    # Precedence (first non-empty wins):
    #   1. Environment variable: STACKPANEL_<PATH_IN_UPPER_SNAKE>
    #   2. CLI query: stackpanel config get <path>
    #   3. Default: passed as second argument
    #
    # Usage:
    #   STATE_DIR=$(sp_get "paths.state" ".stackpanel/state")
    #   KEYS_DIR=$(sp_get "paths.keys" ".stackpanel/state/keys")
    #
    # ==========================================================================
    sp_get() {
      local path="$1"
      local default
      default="''${2:-}"
      
      # Convert path to env var name: paths.local-key -> STACKPANEL_PATHS_LOCAL_KEY
      local env_var
      env_var="STACKPANEL_$(echo "$path" | tr '[:lower:].-' '[:upper:]__')"
      
      # Try env var first (indirect expansion)
      local env_val
      env_val="''${!env_var:-}"
      if [[ -n "$env_val" ]]; then
        echo "$env_val"
        return 0
      fi
      
      # Try CLI query (if stackpanel is available)
      if command -v stackpanel &>/dev/null; then
        local cli_val
        if cli_val=$(stackpanel config get "$path" 2>/dev/null) && [[ -n "$cli_val" ]]; then
          echo "$cli_val"
          return 0
        fi
      fi
      
      # Fall back to default
      echo "$default"
    }
  '';

  # ===========================================================================
  # GETTERS
  #
  # These generate shell code that calls sp_get.
  # ===========================================================================

  # Main getter: $(sp_get "path" "default")
  # If config is available, default is derived from config.stackpanel.<path>
  # Otherwise, you must pass the default explicitly via getWithDefault
  get =
    path:
    let
      default = getDefault path;
    in
    if default == "" then
      throw ''
        cfg.get: No default found for "${path}".
        
        Either:
          1. Pass config when importing cfg.nix:
             cfg = import ./cfg.nix { inherit lib config; };
          2. Use cfg.getWithDefault to specify default explicitly:
             cfg.getWithDefault "paths.state" ".stackpanel/state"
      ''
    else
      ''$(sp_get "${path}" "${default}")'';

  # Getter with explicit default (when config not available)
  getWithDefault = path: default: ''$(sp_get "${path}" "${default}")'';

  # ===========================================================================
  # WELL-KNOWN PATHS
  #
  # Commonly used paths with their defaults.
  # This provides a registry of known variables for discoverability.
  # ===========================================================================

  knownPaths = {
    # Core directories
    "paths.root" = ".stackpanel";
    "paths.state" = ".stackpanel/state";
    "paths.keys" = ".stackpanel/state/keys";
    "paths.gen" = ".stackpanel/gen";

    # Secrets
    "secrets.secrets-dir" = ".stackpanel/secrets";

    # Files
    "paths.state-file" = ".stackpanel/state/stackpanel.json";
    "paths.local-key" = ".stackpanel/state/keys/local.txt";
    "paths.local-pub" = ".stackpanel/state/keys/local.pub";
  };

  # Get a well-known path (uses registry default if config not available)
  getKnown =
    path:
    let
      configDefault = getDefault path;
      registryDefault = knownPaths.${path} or null;
      default = if configDefault != "" then configDefault else registryDefault;
    in
    if default == null then
      throw ''
        cfg.getKnown: "${path}" is not a known path.
        
        Known paths: ${lib.concatStringsSep ", " (builtins.attrNames knownPaths)}
        
        Use cfg.getWithDefault for custom paths.
      ''
    else
      ''$(sp_get "${path}" "${default}")'';

in
{
  inherit bashLib;
  inherit get getWithDefault getKnown;
  inherit pathToEnvVar getDefault;
  inherit knownPaths;
}
