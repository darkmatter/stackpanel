# ==============================================================================
# exports.nix
#
# Consolidated flake exports for stackpanel.
# All user-facing outputs are defined here and imported by flake.nix.
#
# Simplified architecture:
#   - ONE flakeModule (default) that handles everything
#   - Devenv is the shell backend (always)
#   - Config auto-loaded from .stackpanel/
# ==============================================================================
{
  inputs,
  withSystem,
  flake-parts-lib,
  self,
}:
let
  inherit (flake-parts-lib) importApply;

  supportedSystems = [
    "x86_64-linux"
    "aarch64-linux"
    "x86_64-darwin"
    "aarch64-darwin"
  ];
in
{
  inherit supportedSystems;

  # ===========================================================================
  # FLAKE MODULES (for flake-parts users)
  # ===========================================================================
  flakeModules = {
    # Main stackpanel flake-parts module
    # This is THE module - auto-loads config, creates devenv shell, exposes outputs
    # Usage: imports = [ inputs.stackpanel.flakeModules.default ];
    default = importApply ./default.nix {
      localFlake = self;
      inherit withSystem;
    };

    # Alias for backwards compatibility
    devenv = importApply ./default.nix {
      localFlake = self;
      inherit withSystem;
    };

    # Helper module for pure flake evaluation (like `nix flake check`)
    # Reads stackpanel root from a file input for impure-free evaluation
    readStackpanelRoot =
      {
        inputs,
        lib,
        ...
      }:
      {
        config =
          let
            rootContent =
              if inputs ? stackpanel-root then builtins.readFile inputs.stackpanel-root.outPath else "";
          in
          lib.mkIf (rootContent != "") {
            perSystem =
              { lib, ... }:
              {
                devenv.shells = lib.mkDefault {
                  default.stackpanel.root = lib.strings.trim rootContent;
                };
              };
          };
      };
  };

  # ===========================================================================
  # NIXOS MODULES (for NixOS users)
  # ===========================================================================
  nixosModules = {
    default = ./modules/devenv.nix;
    aws = ../stackpanel/services/aws.nix;
    network = ../stackpanel/network/network.nix;
    secrets = ../stackpanel/secrets/default.nix;
    theme = ../stackpanel/lib/theme.nix;
    caddy = ../stackpanel/services/caddy.nix;
    ci = ../stackpanel/apps/ci.nix;
  };

  # ===========================================================================
  # DEVENV MODULES (for devenv users - yaml and flake-parts)
  # ===========================================================================
  # Usage in devenv.shells.default:
  #   imports = [ inputs.stackpanel.devenvModules.default ];
  devenvModules = {
    default = ./modules/devenv.nix;
    # Alias for backwards compatibility
    devshell = ./modules/devenv.nix;
  };

  # ===========================================================================
  # LIBRARY FUNCTIONS
  # ===========================================================================
  lib = {
    # AWS credential helpers
    mkAwsCredScripts = import ../stackpanel/lib/services/aws.nix;

    # Step CA certificate helpers
    mkStepScripts = import ../stackpanel/lib/services/step.nix;
  };

  # ===========================================================================
  # TEMPLATES
  # ===========================================================================
  templates = {
    default = {
      path = ./templates/default;
      description = "Stackpanel + devenv + flake-parts (recommended)";
    };
    minimal = {
      path = ./templates/minimal;
      description = "Stackpanel minimal setup";
    };
    devenv = {
      path = ./templates/devenv;
      description = "Stackpanel + devenv standalone (devenv.yaml)";
    };
  };

  # ===========================================================================
  # STACKPANEL OPTIONS (for IDE/language server support)
  # ===========================================================================
  mkStackpanelOptions =
    nixpkgs:
    nixpkgs.lib.genAttrs supportedSystems (
      system:
      withSystem system (
        { pkgs, ... }:
        let
          lib = pkgs.lib;
          mkOptions =
            modules:
            (lib.evalModules {
              modules = modules ++ [
                { _module.args = { inherit pkgs lib; }; }
              ];
            }).options;
        in
        {
          all = mkOptions [
            ../stackpanel/core/options/default.nix
            { stackpanel.enable = true; }
          ];
        }
      )
    );
}
