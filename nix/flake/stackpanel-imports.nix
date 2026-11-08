# ==============================================================================
# stackpanel-imports.nix — Project-local stackpanel modules + flake addons
#
# Shared by the flake module (default.nix) and the devenv module
# (devenv-module.nix) so both evaluate the same module set.
# ==============================================================================
{
  lib,
  self,
  extraImports ? [ ],
}:
let
  discoveredStackpanelImports =
    if builtins.pathExists (self + "/.stack/modules") then
      [ (self + "/.stack/modules") ]
    else if builtins.pathExists (self + "/.stack/nix") then
      [ (self + "/.stack/nix") ]
    else if builtins.pathExists (self + "/.stackpanel/modules") then
      [ (self + "/.stackpanel/modules") ]
    else if builtins.pathExists (self + "/.stackpanel/nix") then
      [ (self + "/.stackpanel/nix") ]
    else
      [ ];

  # Flake-level adoption offers (templates/_addons) join module-contributed
  # offers under stackpanel.addons so `stack setup` sees one list.
  flakeAddonsModule = {
    stackpanel.addons = (import ./addons.nix { inherit lib; }).initAddons;
  };
in
discoveredStackpanelImports ++ extraImports ++ [ flakeAddonsModule ]
