# ==============================================================================
# default.nix
#
# Entry point for stackpanel devshells.
# Points to the main stackpanel module for use by the flakeModule.
#
# The flakeModule (nix/flake/default.nix) handles all shell creation via devenv.
# This file exists for backwards compatibility and module reference.
# ==============================================================================
{ inputs }:
{
  # Main stackpanel module - imports all features
  # Features only activate when their .enable option is set
  core = ../../stackpanel;
}
