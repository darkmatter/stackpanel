# ==============================================================================
# default.nix
#
# Main entry point for the stackpanel Nix module system.
#
# ==============================================================================
{ lib, ... }:
let
  initshell = lib.concatLines [
    ''
      echo "✅ Stackpanel Nix module system initialized"
    ''
  ];
in
{
  imports = [
    ./devshell/core.nix
    # Core hooks
    ./core
    ./network
    ./secrets
    ./services
    # SOPS helper
    ./tui
  ];
}
