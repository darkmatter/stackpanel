# ==============================================================================
# default.nix
#
# Variables module - workspace variables and backend configuration.
# ==============================================================================
{ ... }:
{
  imports = [
    ./variables-options.nix
    ./variables-backend-options.nix
  ];
}
