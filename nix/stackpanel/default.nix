# ==============================================================================
# default.nix
#
# Main entry point for the stackpanel Nix module system.
#
# ==============================================================================
{ lib, ... }: let

  initshell = lib.concatLines [
    ''
      echo "✅ Stackpanel Nix module system initialized"
    ''
  ];
  in {
  imports = [
    # SOPS helper
    ./packages/sops
    ./core/default.nix
  ];

  stackpanel.devshell.hooks.before = [

  ];
}