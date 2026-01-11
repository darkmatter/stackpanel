# ==============================================================================
# binary-cache.nix
#
# Binary cache configuration options.
#
# Enables local configuration for Cachix and other binary cache settings.
# ==============================================================================
{ lib, ... }:
{
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
}
