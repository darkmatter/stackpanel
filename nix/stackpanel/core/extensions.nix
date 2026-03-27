# ==============================================================================
# extensions.nix
#
# Stackpanel extension configuration split into smaller pieces for maintainability.
#
# - extensions-parts/types.nix: Extension option types
# - extensions-parts/computed.nix: Derived/auto-discovered extension data
# - extensions-parts/options.nix: Public option declarations
# - extensions-parts/config.nix: Compatibility conversion to stackpanel.modules
# ==============================================================================
{
  lib,
  config,
  ...
}:
let
  cfg = config.stackpanel;
  types = import ./extensions-parts/types.nix { inherit lib; };
  computed = import ./extensions-parts/computed.nix {
    inherit lib cfg;
    extensionSrc = import ../lib/extension-src.nix { inherit lib; };
  };
in
(import ./extensions-parts/options.nix {
  inherit lib types computed;
})
// import ./extensions-parts/config.nix {
  inherit lib cfg;
}
