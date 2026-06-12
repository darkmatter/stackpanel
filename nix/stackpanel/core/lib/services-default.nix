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
#   - globalServices: Global singleton service configuration (requires pkgs + integrations)
#
# Service implementations live under nix/stackpanel/integrations/services/.
# ==============================================================================
{
  lib,
  pkgs ? null,
}:
{
  # Port computation utilities (pure, no pkgs needed)
  ports = import ../../lib/ports.nix { inherit lib; };

  # Global services configuration (requires pkgs and integration libraries)
  globalServices =
    if pkgs != null then
      let
        servicesLib = import ../../integrations/services/lib.nix { inherit pkgs lib; };
        caddyLib = import ../../integrations/services/caddy { inherit pkgs lib; };
      in
      import ./global-services.nix {
        inherit
          pkgs
          lib
          servicesLib
          caddyLib
          ;
      }
    else
      throw "stackpanel.core.globalServices requires pkgs to be passed";
}
