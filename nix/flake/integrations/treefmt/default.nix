# ==============================================================================
# integrations/treefmt — root packages + formatter when includeRootOutputs
# ==============================================================================
{
  localFlake,
  localInputs,
  inputs,
}:
let
  available = localInputs ? treefmt-nix;
in
{
  inherit available;

  flakeModules = [ ];

  perSystem =
    {
      lib,
      pkgs,
      self,
      includeRootOutputs,
      ...
    }:
    lib.mkIf (available && includeRootOutputs) (
      let
        rootPackages = import ../../packages.nix { inherit pkgs; };
        treefmtEval = localInputs.treefmt-nix.lib.evalModule pkgs {
          projectRootFile = "flake.nix";
          programs = {
            nixfmt.enable = true;
            deadnix.enable = true;
            statix.enable = true;
            gofumpt.enable = true;
            goimports.enable = true;
            golines.enable = true;
            golines.maxLength = 88;
            golines.tabLength = 2;
          };
        };
      in
      {
        packages = lib.mapAttrs (_: lib.mkDefault) rootPackages;
        checks = {
          inherit (rootPackages) stackpanel;
          default-package = rootPackages.default;
          formatting = treefmtEval.config.build.check self;
        };
        formatter = treefmtEval.config.build.wrapper;
      }
    );
}
