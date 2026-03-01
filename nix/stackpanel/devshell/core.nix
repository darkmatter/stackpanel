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
    ./scripts.nix
    ./codegen.nix
    ./clean.nix
    ./direnv.nix
    ./tui.nix
    ./bin.nix
    ./profile.nix
    ./gc-roots.nix
  ];
}
