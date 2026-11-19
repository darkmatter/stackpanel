# ==============================================================================
# options-doc.nix
#
# Shared helpers for generating nixosOptionsDoc output for Stackpanel options.
# ==============================================================================
{
  pkgs,
  lib,
}:
{
  options ? null,
  modules ? [ ../core/options ],
  extraModules ? [ ],
  enableModule ? {
    stackpanel.enable = true;
  },
  moduleArgs ? { },
  specialArgs ? { },
}:
let
  moduleLib = import ../../flake/module-lib.nix (specialArgs.lib or lib);
  evalResult =
    if options == null then
      lib.evalModules {
        modules = map moduleLib.stackpanel.normalizeModule (modules ++ extraModules) ++ [
          { _module.args = moduleArgs; }
          enableModule
        ];
        specialArgs = {
          pkgs = moduleArgs.pkgs or pkgs;
          inputs = moduleArgs.inputs or { };
          self = moduleArgs.self or { outPath = ../.; };
          localFlake = moduleArgs.localFlake or null;
          isGlobalEval = false;
        }
        // specialArgs
        // {
          lib = moduleLib;
        };
      }
    else
      null;

  stackpanelOptions = if options == null then evalResult.options.stackpanel or { } else options;

  transformOptions =
    opt:
    opt
    // {
      declarations = map (
        decl:
        let
          declStr = toString decl;
        in
        {
          name = declStr;
          url = null;
        }
      ) (opt.declarations or [ ]);
    };
in
pkgs.nixosOptionsDoc {
  options = builtins.removeAttrs stackpanelOptions [ "_module" ];
  inherit transformOptions;
  warningsAreErrors = false;
}
