# ==============================================================================
# default.nix
#
# Entry point for stackpanel devshells. Exports the core devshell module,
# the mkDevShell function for creating development shells, and feature modules.
#
# Usage:
#   devshell = import ./devshells { inherit inputs; };
#   shell = devshell.mkDevShell { inherit pkgs; modules = [ ... ]; };
#
# Exports:
#   - core: The core devshell module providing schema, commands, codegen, files
#   - mkDevShell: Function to create a development shell with given modules
#   - features: Optional feature modules (aws, step, etc.)
# ==============================================================================
{ inputs }:
{
  # Core devshell module - provides schema, commands, codegen, files
  core = ../../stackpanel/devshell/core.nix;

  mkDevShell = { pkgs, modules ? [], specialArgs ? {} }:
    (import ./mkDevShell.nix { inherit pkgs; }) { inherit modules specialArgs; };

  # @TODO wire in modules
  features = {
    # aws = ../../stackpanel/features/aws/devshell.nix;
    # step = ../../stackpanel/features/step/devshell.nix;
  };
}