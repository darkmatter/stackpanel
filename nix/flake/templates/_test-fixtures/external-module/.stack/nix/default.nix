{ lib, pkgs, ... }:
{
  imports = [
    (lib.stackpanel.mkModule {
      name = "fixture-preview";
      meta.name = "Preview fixture";
      packages = [ (pkgs.writeShellScriptBin "fixture-preview-tool" ":") ];
      config = _: {
        stackpanel = {
          files.entries."preview.txt".text = "preview";
          services.fixture-preview = {
            enable = true;
            command = "fixture-preview-tool";
          };
        };
      };
    })
  ];
  stackpanel = {
    devshell.packages = [ (pkgs.writeShellScriptBin "fixture-local-nix" ":") ];
    nixosModules.fixture-local-nix = { };
  };
}
