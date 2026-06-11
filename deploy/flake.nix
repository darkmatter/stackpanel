# ==============================================================================
# deploy/flake.nix — Stackpanel internal deployment sub-flake
#
# Exposes nixosConfigurations + colmenaHive without forcing the main flake to
# evaluate internal host/VM configs (see stackpanel.deployment.flakeOutputs).
#
# Usage:
#   nix eval ./deploy#nixosConfigurations.<machine>.config.system.build.toplevel.drvPath
#   colmena apply --flake ./deploy
#   nixos-rebuild switch --flake ./deploy#<machine> --target-host ...
# ==============================================================================
{
  description = "Stackpanel NixOS deployment configurations (internal sub-flake)";

  inputs = {
    stackpanel.url = "path:..";
  };

  outputs =
    { stackpanel, ... }:
    let
      globalOutputs = import ../nix/flake/global-outputs.nix {
        self = stackpanel;
        inputs = stackpanel.flakeInputs // { self = stackpanel; };
        stackpanelImports = [
          (
            { lib, ... }:
            {
              stackpanel.deployment.flakeOutputs.expose = lib.mkForce true;
            }
          )
        ];
      };
    in
    {
      inherit (globalOutputs) nixosConfigurations colmenaHive;
    };
}
