# Bundled modules use the same metadata registry as local and flake inputs.
# A leading dot or underscore marks a private directory (including _template).
{ lib, ... }:
let
  modules = lib.filterAttrs (
    name: type: type == "directory" && !(lib.hasPrefix "." name || lib.hasPrefix "_" name)
  ) (builtins.readDir ./.);
in
{
  imports = lib.mapAttrsToList (name: _: ./${name}) modules;
}
