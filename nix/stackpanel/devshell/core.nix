# ==============================================================================
# core.nix
#
# Core devshell module aggregator.
#
# This file imports all devshell submodules to compose the complete devshell
# functionality: schema definitions, command builders, code generation, and
# file generation systems.
# ==============================================================================
{ ... }:
{
  imports = [
    ./schema.nix
    ./commands.nix
    ./codegen.nix
    ./files.nix
  ];
}