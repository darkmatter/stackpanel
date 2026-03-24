# ==============================================================================
# load-config.nix - Stackpanel config path discovery
#
# Returns the path to the stackpanel config file, or null if none found.
# Callers are responsible for importing the path and handling the function-vs-
# attrset case (function configs take { pkgs, lib } or { lib }).
#
# Discovery order:
#   1. .stackpanel/_internal.nix  (machine-generated, full NixOS module context)
#   2. .stackpanel/config.nix     (human-editable)
# ==============================================================================
{ self }:
let
  internal = self + "/.stackpanel/_internal.nix";
  simple   = self + "/.stackpanel/config.nix";
in
if      builtins.pathExists internal then internal
else if builtins.pathExists simple   then simple
else null
