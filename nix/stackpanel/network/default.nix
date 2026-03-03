# ==============================================================================
# default.nix
#
# Network module index - aggregates all network-related modules.
# ==============================================================================
{ ... }:
{
  imports = [
    ./dns.nix
    ./dns-options.nix
    ./network.nix
    ./ports.nix
    ./ports-options.nix
    ./step-ca-options.nix
  ];
}
