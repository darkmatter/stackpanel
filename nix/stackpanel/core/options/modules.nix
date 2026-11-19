# ==============================================================================
# modules.nix
#
# Stackpanel Module System - split into focused parts for readability.
#
# - options/modules/types.nix: Nix type definitions.
# - options/modules/computed.nix: Derived/computed module values.
# - options/modules/options.nix: Public option declarations.
# ==============================================================================
{
  lib,
  config,
  ...
}@args:
let
  cfg = config.stackpanel;
  types = import ./modules/types.nix { inherit lib; };
  computed = import ./modules/computed.nix {
    inherit lib cfg;
    inputs = args.inputs or { };
  };
in
import ./modules/options.nix {
  inherit lib computed;
  inherit types;
}
