# Core library functions for stackpanel
#
# Pure logic that works with any Nix module system (flake-parts, devenv, NixOS, etc.)
# No side effects - these are pure functions callable from both flake and devenv adapters.
#
# Usage:
#   let core = import ./core { inherit lib pkgs; };
#   in core.ports.computeBasePort { name = "myproject"; }
#
{
  lib,
  pkgs ? null,
}: {
  # Port computation utilities (pure, no pkgs needed)
  ports = import ./ports.nix { inherit lib; };

  # Global services configuration (requires pkgs)
  globalServices =
    if pkgs != null
    then import ./global-services.nix { inherit pkgs lib; }
    else throw "stackpanel.core.globalServices requires pkgs to be passed";

  # Service definitions helpers (requires pkgs)
  # These are wrappers that call into lib/services/
  services =
    if pkgs != null
    then import ../services { inherit pkgs lib; }
    else throw "stackpanel.core.services requires pkgs to be passed";
}
