# ==============================================================================
# default.nix
#
# Entry point for stackpanel devshells. Uses nix/stackpanel/default.nix as the
# single source of truth for all modules.
#
# Usage:
#   devshell = import ./devshells { inherit inputs; };
#
# Exports:
#   - core: The main stackpanel module entrypoint
#   - mkDevShell: Function to create a development shell with given modules
# ==============================================================================
{ inputs }:
{
  # Main stackpanel module - imports all features
  # Features only activate when their .enable option is set
  core = ../../stackpanel;

  # mkDevShell for standalone nix develop usage (without devenv)
  mkDevShell =
    {
      pkgs,
      modules ? [ ],
      specialArgs ? { },
    }:
    (import ./mkDevShell.nix { inherit pkgs; }) {
      modules = [ ../../stackpanel ] ++ modules;
      inherit specialArgs;
    };
}
