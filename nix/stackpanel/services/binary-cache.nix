# ==============================================================================
# binary-cache.nix
#
# Configure binary cache tooling (Cachix) for development shells.
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
