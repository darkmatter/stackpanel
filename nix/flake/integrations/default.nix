# ==============================================================================
# integrations/default.nix — Flake-level external integration registry
#
# Each integration under this directory exports:
#
#   {
#     available = bool;                    # required input present
#     flakeModules = [ ... ];              # imported when available
#     flakeConfig ? { lib, ... }: { ... }; # optional top-level mkMerge arm
#     perSystem ? ctx: { ... };            # after stackpanel eval
#     extraShellPackages ? ctx: [ pkgs ];  # added to devShells.default
#   }
#
# Context passed to perSystem / extraShellPackages:
#   system, pkgs, lib, config, self, inputs, localFlake, localInputs,
#   spConfig, loadedConfig, includeRootOutputs, eval
#
# To add an integration: create integrations/<id>/default.nix and register it
# in the `all` attrset below. See README.md.
# ==============================================================================
{
  localFlake,
  localInputs,
  inputs,
  lib,
}:
let
  all = {
    prelude = import ./prelude {
      inherit localFlake localInputs inputs;
    };
    process-compose = import ./process-compose {
      inherit localFlake localInputs inputs;
    };
    git-hooks = import ./git-hooks {
      inherit localFlake localInputs inputs;
    };
    treefmt = import ./treefmt {
      inherit localFlake localInputs inputs;
    };
  };

  values = builtins.attrValues all;

  availableValues = builtins.filter (i: i.available or false) values;
in
{
  integrations = all;

  flakeModules = lib.concatMap (i: i.flakeModules or [ ]) availableValues;

  # Top-level config arms (e.g. process-compose separate perSystem).
  flakeConfigs = lib.concatMap (
    i: if i ? flakeConfig then [ i.flakeConfig ] else [ ]
  ) availableValues;

  mkPerSystem = ctx: lib.mkMerge (map (i: if i ? perSystem then i.perSystem ctx else { }) values);

  extraShellPackages =
    ctx: lib.concatMap (i: if i ? extraShellPackages then i.extraShellPackages ctx else [ ]) values;
}
