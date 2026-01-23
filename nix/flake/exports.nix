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

  # Function to get stackpanel options.
  # Usage: inputs.stackpanel.lib.getOptions { inherit pkgs; }
  #
  # Returns the full stackpanel options attrset for introspection.
  getOptions =
    { pkgs }:
    let
      lib = pkgs.lib;
      evaluated = lib.evalModules {
        modules = [
          ../stackpanel
          {
            _module.args = {
              inherit pkgs lib;
              inputs = { };
            };
            stackpanel.enable = true;
            stackpanel.name = "options-eval";
          }
        ];
      };
    in
    evaluated.options.stackpanel;
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
    #
    # The file can contain:
    #   - An absolute path (written by .envrc for impure evaluation)
    #   - "." to use the flake source directory (for pure evaluation)
    #
    # For pure evaluation to work, the file must be tracked by git (not in .gitignore)
    #
    # This module sets config.stackpanel.projectRoot at the flake level.
    # Users who need devenv.root for pure evaluation should set it separately.
    readStackpanelRoot =
      {
        inputs,
        lib,
        ...
      }:
      let
        hasInput = inputs ? stackpanel-root;
        rawContent = if hasInput then builtins.readFile inputs.stackpanel-root.outPath else "";
        rootContent = lib.strings.trim rawContent;
        # The input's outPath points to the file itself, so get its directory
        # which is the flake source root
        flakeSourceDir = if hasInput then builtins.dirOf inputs.stackpanel-root.outPath else "";
        # If content is "." use the flake source directory
        # Otherwise use the absolute path from the file
        effectiveRoot =
          if rootContent == "." then
            flakeSourceDir
          else if rootContent != "" then
            rootContent
          else
            null;
      in
      {
        # Set the flake-level stackpanel.projectRoot option
        # The main flakeModule will read this and set devenv.root
        config.stackpanel.projectRoot = lib.mkIf (effectiveRoot != null) effectiveRoot;
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

    # Fly.io OIDC to AWS authentication
    # Usage: inputs.stackpanel.lib.flyOidc { pkgs = pkgsLinux; }
    flyOidc = import ../stackpanel/lib/services/fly-oidc.nix;

    # Wrap devenv input to extract schema and inject into modules
    # This enables bidirectional mapping: devenv options ↔ stackpanel state
    #
    # Usage in your flake.nix:
    #   let
    #     wrappedDevenv = inputs.stackpanel.lib.wrapDevenv { inherit inputs; };
    #   in {
    #     devShells.default = wrappedDevenv.lib.mkShell { ... };
    #     # Access schema: wrappedDevenv.schema
    #   }
    #
    # The wrapped devenv:
    #   - Extracts available services, languages, pre-commit hooks
    #   - Injects schema via specialArgs to all modules
    #   - Exposes schema for state.json serialization
    wrapDevenv = import ../lib/wrap-devenv.nix;

    # Get stackpanel module options for introspection
    # Usage: inputs.stackpanel.lib.getOptions { inherit pkgs; }
    inherit getOptions;
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
}
