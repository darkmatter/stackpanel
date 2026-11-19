# Module discovery is shared by global, per-system and devenv evaluations.
# Never ask the inner module fixed point which modules to import.
{
  lib,
  self,
  inputs,
  extraImports ? [ ],
  autoImportInputs ? true,
  registries ? [ ],
}:
let
  sdkLib = import ./module-lib.nix lib;
  # A project can also set autoImportInputs in its .stack/config.nix (or tree).
  # Like Nix 'imports', this setting must be independent of the final config.
  project =
    if self == null then
      { }
    else
      (import ./load-config.nix { inherit self inputs; }).evalResolved {
        lib = sdkLib;
        pkgs = throw "stackpanel: import discovery cannot depend on pkgs";
        config = throw "stackpanel: import discovery cannot depend on the evaluated config";
      };
  discover = autoImportInputs && (project.autoImportInputs or true);

  local = lib.optionals (self != null) (
    builtins.filter builtins.pathExists [
      (self + "/.stack/modules")
      (self + "/.stack/nix")
    ]
  );
  external = lib.filterAttrs (_: input: input ? stackpanelModules.default) (
    removeAttrs inputs [
      "self"
      "stackpanel"
    ]
  );
in
local
++ lib.optionals discover (
  map (input: sdkLib.stackpanel.normalizeModule input.stackpanelModules.default) (
    builtins.attrValues external
  )
)
++ map sdkLib.stackpanel.normalizeModule extraImports
++ [
  {
    stackpanel = {
      autoImportInputs = lib.mkForce discover;
      inherit registries;
      addons = (import ./addons.nix { inherit lib; }).initAddons;
    };
  }
]
