{ lib, ... }:
{
  options.stackpanel = {
    autoImportInputs = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Import stackpanelModules.default from project flake inputs. Disable to
        choose modules explicitly with stackpanel.imports. Does not affect
        local modules or static flake-parts adapters and nixpkgs overlays.
      '';
    };
    registries = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "https://example.org/registry.v1.json" ];
      description = "Ordered URLs of additional module registry catalogs for this project.";
    };
  };
}
