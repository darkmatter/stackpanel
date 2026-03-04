# ==============================================================================
# default.nix
#
# Network module index - aggregates all network-related modules.
# ==============================================================================
{ ... }:
{
  imports = [
    ./dns.nix
    ./network.nix
    ./ports.nix
  ];
}
