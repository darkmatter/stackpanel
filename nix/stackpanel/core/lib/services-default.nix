# ==============================================================================
# default.nix
#
# Core library functions for stackpanel services.
#
# Pure logic that works with any Nix module system (flake-parts, devenv, NixOS,
# etc.). No side effects - these are pure functions callable from both flake
# and devenv adapters.
#
# Exports:
#   - ports: Port computation utilities (pure, no pkgs needed)
#   - globalServices: Global singleton service configuration (requires pkgs)
#   - services: Service registry and factory functions (requires pkgs)
#
# Usage:
#   let core = import ./default.nix { inherit lib pkgs; };
#   in core.ports.computeBasePort { name = "myproject"; }
# ==============================================================================
{
  lib,
  pkgs ? null,
}:
{
  # Port computation utilities (pure, no pkgs needed)
  ports = import ../../lib/ports.nix { inherit lib; };

  # Global services configuration (requires pkgs)
  globalServices =
    if pkgs != null then
      import ./global-services.nix { inherit pkgs lib; }
    else
      throw "stackpanel.core.globalServices requires pkgs to be passed";

  # Service registry and factory functions (requires pkgs)
  # Implementations live in nix/stackpanel/services/{postgres,redis,minio}/
  services =
    if pkgs != null then
      import ./services.nix { inherit pkgs lib; }
    else
      throw "stackpanel.core.services requires pkgs to be passed";
}
