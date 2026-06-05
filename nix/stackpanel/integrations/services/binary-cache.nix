# ==============================================================================
# binary-cache.nix
#
# Binary cache module - configure Cachix for development shells.
#
# Options + implementation colocated in a single self-contained module.
# ==============================================================================
{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.stackpanel.binary-cache;
  cachixCfg = cfg.cachix;
  tokenPathValue = if cachixCfg.token-path == null then "" else toString cachixCfg.token-path;
in
{
  # ── Options ──────────────────────────────────────────────────────────────────
  options.stackpanel.binary-cache = {
    enable = lib.mkEnableOption "Binary cache configuration";

    cachix = {
      enable = lib.mkEnableOption "Cachix integration";

      cache = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Cachix cache name for pushing binaries";
      };

      token-path = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to a Cachix auth token file";
      };
    };
  };

  # ── Config ───────────────────────────────────────────────────────────────────
  config = lib.mkIf cfg.enable {
    stackpanel.devshell.packages = lib.mkIf cachixCfg.enable [ pkgs.cachix ];

    stackpanel.devshell.hooks.before = lib.mkAfter [
      ''
        if [[ "${lib.boolToString cachixCfg.enable}" == "true" ]]; then
          if [[ -n "${cachixCfg.cache}" ]]; then
            export CACHIX_CACHE_NAME="${cachixCfg.cache}"
          fi

          if [[ -n "${tokenPathValue}" ]]; then
            if [[ -f "${tokenPathValue}" ]]; then
              export CACHIX_AUTH_TOKEN="$(cat "${tokenPathValue}")"
            fi
          fi
        fi
      ''
    ];
  };
}
