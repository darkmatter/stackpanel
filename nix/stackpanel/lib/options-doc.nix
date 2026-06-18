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
  evalResult =
    if options == null then
      lib.evalModules {
        modules =
          modules
          ++ extraModules
          ++ [
            {
              _module.args = {
                inherit pkgs lib;
              }
              // moduleArgs;
            }
            enableModule
          ];
        specialArgs = {
          inherit lib;
        }
        // specialArgs;
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
