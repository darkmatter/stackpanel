# ==============================================================================
# default.nix
#
# Network module index - aggregates all network-related modules.
# ==============================================================================
{ ... }:
{
  imports = [
    ./network.nix # Step CA certificates
    ./ports.nix # Deterministic port computation
    ./dns.nix # Local DNS configuration (Apple container, etc.)
  ];
}
