# ==============================================================================
# agenix.nix
#
# Agenix compatibility layer (minimal).
#
# Stackpanel now encrypts SOPS files directly to recipient public keys.
# This module is kept for backwards compatibility but is largely a no-op.
# ==============================================================================
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.stackpanel.secrets;
in
{
  options.stackpanel.secrets = {
    secrets-nix-content = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "# Legacy secrets.nix is no longer generated\n{}\n";
      description = ''
        Deprecated: secrets.nix is no longer generated.
        Secrets are now stored in group YAML files encrypted via SOPS.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    stackpanel.secrets.secrets-nix-content = "# Legacy secrets.nix is no longer generated\n{}\n";
  };
}
