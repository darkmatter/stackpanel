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
#   - services: Service definitions and helpers (requires pkgs)
#
# Usage:
#   let core = import ./services { inherit lib pkgs; };
#   in core.ports.computeBasePort { name = "myproject"; }
# ==============================================================================
{
  lib,
  pkgs ? null,
}:
{
  # Port computation utilities (pure, no pkgs needed)
  ports = import ./ports.nix { inherit lib; };

  # Global services configuration (requires pkgs)
  globalServices =
    if pkgs != null then
      import ./global-services.nix { inherit pkgs lib; }
    else
      throw "stackpanel.core.globalServices requires pkgs to be passed";

  # Service definitions helpers (requires pkgs)
  # These are wrappers that call into lib/services/
  services =
    if pkgs != null then
      import ./services { inherit pkgs lib; }
    else
      throw "stackpanel.core.services requires pkgs to be passed";
}
