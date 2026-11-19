{ pkgs, ... }:
{
  stackpanel = {
    devshell.packages = [ (pkgs.writeShellScriptBin "fixture-local-modules" ":") ];
    nixosModules.fixture-local-modules = { };
  };
}
