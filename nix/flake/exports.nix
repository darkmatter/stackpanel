# ==============================================================================
# exports.nix
#
# Consolidated flake exports for stackpanel.
# All user-facing outputs (nixosModules, devenvModules, lib, templates) are
# defined here and imported by flake.nix.
#
# This keeps flake.nix focused on:
#   - inputs/nixConfig (required to be in flake.nix)
#   - local development configuration (dogfooding)
#   - importing these exports
# ==============================================================================
{
  inputs,
  withSystem,
  flake-parts-lib,
  self,
}:
let
  inherit (flake-parts-lib) importApply;

  # Devshell utilities (core module, mkDevShell, features)
  devshell = import ./devshells { inherit inputs; };

  # Devenv module (stackpanel adapter for devenv)
  devenv = import ./devenv.nix;

  supportedSystems = [
    "x86_64-linux"
    "aarch64-linux"
    "x86_64-darwin"
    "aarch64-darwin"
  ];
in
{
  # Re-export for use in flake.nix
  inherit devshell devenv supportedSystems;

  # ===========================================================================
  # FLAKE MODULES (for flake-parts users)
  # ===========================================================================
  flakeModules = {
    # Main stackpanel flake-parts module
    # Usage: imports = [ inputs.stackpanel.flakeModules.default ];
    default = importApply ./default.nix {
      localFlake = self;
      inherit withSystem devshell;
    };

    # Alias for devenv module (backwards compatibility)
    # Usage: imports = [ inputs.stackpanel.flakeModules.devenv ];
    devenv = importApply ./default.nix {
      localFlake = self;
      inherit withSystem devshell;
    };

    # Native Nix devShell module (without devenv dependency)
    # Usage: imports = [ inputs.stackpanel.flakeModules.native ];
    # Then set: perSystem = { ... }: { stackpanel.enable = true; };
    native = importApply ./modules/native.nix {
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
  # Usage: imports = [ inputs.stackpanel.nixosModules.default ];
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
  # Usage in flake-parts:
  #   devenv.shells.default = {
  #     imports = [ inputs.stackpanel.devenvModules.default ];
  #   };
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

    # Create a development shell with stackpanel modules
    # Usage: stackpanel.lib.mkDevShell { inherit pkgs; modules = [...]; }
    mkDevShell =
      {
        pkgs,
        modules ? [ ],
        specialArgs ? { },
      }:
      (import ../stackpanel/devshell { inherit pkgs; }) {
        inherit modules specialArgs;
      };

    # Export feature modules for consumers
    devshellModules = devshell.devshellModules or { };
  };

  # ===========================================================================
  # TEMPLATES
  # ===========================================================================
  templates = {
    default = {
      path = ./templates/default;
      description = "Stackpanel + devenv + flake-parts (recommended)";
    };
    native = {
      path = ./templates/native;
      description = "Stackpanel + native Nix shell (no devenv)";
    };
    devenv = {
      path = ./templates/devenv;
      description = "Stackpanel + devenv standalone (devenv.yaml)";
    };
    minimal = {
      path = ./templates/minimal;
      description = "Stackpanel + devenv without flake-parts";
    };
  };

  # ===========================================================================
  # STACKPANEL OPTIONS (for IDE/language server support)
  # ===========================================================================
  # Usage: (builtins.getFlake (toString ./.)).stackpanelOptions.${system}.all
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
