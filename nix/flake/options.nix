# ==============================================================================
# options.nix — Flake-level stackpanel.* options (projectRoot, imports, …)
# ==============================================================================
{ flake-parts-lib, lib, ... }:
let
  inherit (flake-parts-lib) mkPerSystemOption;
in
{
  options.stackpanel = {
    projectRoot = lib.mkOption {
      type = lib.types.nullOr (lib.types.either lib.types.path lib.types.str);
      default = null;
      description = "Project root path. Defaults to the flake source root.";
    };

    imports = lib.mkOption {
      type = lib.types.listOf lib.types.unspecified;
      default = [ ];
      description = "Additional stackpanel module imports applied to global and per-system evaluations.";
    };

    includeRootOutputs = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to expose Stackpanel's own package, formatter, and deployment test outputs.";
    };
  };

  options.perSystem = mkPerSystemOption (
    { lib, ... }:
    {
      options.stackpanel = {
        imports = lib.mkOption {
          type = lib.types.listOf lib.types.unspecified;
          default = [ ];
          description = "Additional per-system stackpanel module imports.";
        };
      };
    }
  );
}
