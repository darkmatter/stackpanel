# ==============================================================================
# devshell.nix (flake-parts module)
#
# Flake-parts module that integrates stackpanel devshells with the flake-parts
# module system. Provides the stackpanel.devshell option namespace for
# declaratively configuring development shells.
#
# Usage in flake.nix:
#   imports = [ inputs.stackpanel.flakeModules.devshell ];
#   stackpanel.devshell = {
#     enable = true;
#     shellName = "default";
#     modules = [ ./my-devshell-module.nix ];
#   };
#
# Options:
#   - enable: Enable stackpanel devshell integration
#   - shellName: Name of the devShell output (default: "default")
#   - modules: List of devshell modules to include
#   - specialArgs: Extra arguments passed to module evaluation
# ==============================================================================
{ localFlake, withSystem, devshell }:
{ config, lib, ... }:
let
  cfg = config.stackpanel.devshell;
  types = lib.types;
in
{
  options.stackpanel.devshell = {
    enable = lib.mkEnableOption "Stackpanel devShells via flake-parts";

    shellName = lib.mkOption { type = types.str; default = "default"; };

    modules = lib.mkOption {
      type = types.listOf types.deferredModule;
      default = [];
    };

    specialArgs = lib.mkOption {
      type = types.attrs;
      default = {};
    };
  };

  config = lib.mkIf cfg.enable {
    perSystem = { pkgs, system, ... }: {
      devShells.${cfg.shellName} =
        devshell.mkDevShell {
          inherit pkgs;
          modules = cfg.modules;
          specialArgs = cfg.specialArgs // { inherit localFlake withSystem system; };
        };
    };
  };
}