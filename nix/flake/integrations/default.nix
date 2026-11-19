# Normalize bundled adapters and consumer flake metadata into a single list
# of hooks. Only input outputs (never the config fixed point) may determine
# imports and overlays: flake-parts needs them before perSystem exists.
{
  localFlake,
  localInputs,
  inputs,
  lib,
}:
let
  bundled =
    lib.mapAttrsToList
      (
        name: _:
        import (./. + "/${name}") {
          inherit localFlake localInputs inputs;
        }
      )
      (
        lib.filterAttrs (
          name: type: type == "directory" && builtins.pathExists (./. + "/${name}/default.nix")
        ) (builtins.readDir ./.)
      );
  external =
    lib.mapAttrsToList
      (
        _: input:
        let
          meta = input.stackpanelModuleMeta or { };
        in
        meta
        // {
          overlays = meta.overlays or (lib.optional (input ? overlays.stackpanel) input.overlays.stackpanel);
        }
      )
      (
        removeAttrs inputs [
          "self"
          "stackpanel"
        ]
      );
  hooks = builtins.filter (hook: hook.available or true) (bundled ++ external);
in
{
  overlays = lib.concatMap (hook: hook.overlays or [ ]) hooks;
  flakeModules = lib.concatMap (hook: hook.flakeModules or [ ]) hooks;
  flakeConfigs = lib.concatMap (hook: lib.optional (hook ? flakeConfig) hook.flakeConfig) hooks;
  mkPerSystem =
    ctx: lib.mkMerge (map (hook: hook.perSystem ctx) (builtins.filter (hook: hook ? perSystem) hooks));
  extraShellPackages =
    ctx:
    lib.concatMap (hook: if hook ? extraShellPackages then hook.extraShellPackages ctx else [ ]) hooks;
}
