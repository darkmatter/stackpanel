# ==============================================================================
# services/default.nix
#
# Development services — options and implementations co-located.
#
# Imports both option definitions (*-options.nix) and implementation modules
# for AWS, Caddy, binary cache, global services, healthchecks, and the
# canonical service type system.
# ==============================================================================
{...}: {
  imports = [
    ./aws
    ./binary-cache.nix
    ./caddy.nix
    ./caddy/options.nix
    ./global-services.nix
    ./global-services-options.nix
    ./portless.nix
    ./security-healthchecks.nix
    ./services-options.nix
  ];
}
