# ==============================================================================
# addons.nix - Flake-level adoption offers
#
# Each directory under templates/_addons/<id>/ declares one addon in addon.nix:
# metadata, a question, a revision, and a config mutation. Directories whose
# name starts with "_" (e.g. _template) are scaffolding and never offered.
#
# The same map is exposed two ways:
#   - `lib.initAddons` (exports.nix), so a fresh repo with no evaluable project
#     config can still be offered addons by `stack setup`;
#   - injected into every stackpanel evaluation as `stackpanel.addons` (see
#     default.nix), so inside a project they sit next to module-contributed
#     offers in one list and reach the CLI through the config JSON.
#
# Addons no longer carry a `files` payload: anything worth shipping is a
# module, which gains drift-checking and revert that a raw file drop never had.
# ==============================================================================
{ lib }:
let
  addonsDir = ./templates/_addons;

  isLive = name: type: type == "directory" && !lib.hasPrefix "_" name;

  load =
    id:
    let
      spec = import (addonsDir + "/${id}/addon.nix");
    in
    (builtins.removeAttrs spec [
      "files"
      "jsonOps"
    ])
    // {
      id = spec.id or id;
      revision = spec.revision or 1;
    };
in
{
  inherit addonsDir;

  # { "<id>" = { id; revision; question; config ? {}; }; } for every live addon.
  initAddons =
    if !builtins.pathExists addonsDir then
      { }
    else
      lib.mapAttrs (id: _: load id) (lib.filterAttrs isLive (builtins.readDir addonsDir));
}
