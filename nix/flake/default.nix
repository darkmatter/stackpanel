# ==============================================================================
# flake-module.nix
#
# Stackpanel flake-parts module for external users to import into their flakes.
# Provides stackpanel options when used with devenv + flake-parts.
#
# This module uses the "importApply" pattern to get the localFlake reference.
# The outer function receives args from importApply in flake.nix, while the
# inner function is the actual flake-parts module with user's flake context.
#
# Usage in user's flake.nix:
#   imports = [
#     inputs.devenv.flakeModule
#     inputs.stackpanel.flakeModules.default
#   ];
# ==============================================================================
# Stackpanel flake-parts module
#
# This module is for USERS to import into their flakes.
# It provides stackpanel options when used with devenv + flake-parts.
#
# Usage in user's flake.nix:
#
#   {
#     inputs = {
#       nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
#       flake-parts.url = "github:hercules-ci/flake-parts";
#       devenv.url = "github:cachix/devenv";
#       stackpanel.url = "github:darkmatter/stackpanel";
#     };
#
#     outputs = inputs@{ flake-parts, ... }:
#       flake-parts.lib.mkFlake { inherit inputs; } {
#         imports = [
#           inputs.devenv.flakeModule
#           inputs.stackpanel.flakeModules.default  # <-- this module
#         ];
#
#         systems = [ "x86_64-linux" "aarch64-darwin" ];
#
#         perSystem = { ... }: {
#           devenv.shells.default = {
#             imports = [ inputs.stackpanel.devenvModules.default ];
#             stackpanel.enable = true;
#             # User's stackpanel config here
#           };
#         };
#       };
#   }
#
# This uses the "importApply" pattern to get the localFlake reference.
# The outer function receives args from importApply in flake.nix.
localFlake:
# The inner function is the actual flake-parts module.
# These args (self, inputs, lib, etc.) refer to the USER's flake.
{
  lib,
  self,
  inputs,
  config,
  ...
}:
{
  imports = [
    # Import stackpanel options (pkgs-free, safe for flake-parts top-level)
    ../stackpanel/core/options
  ]
  ++ lib.optional (inputs ? process-compose-flake) inputs.process-compose-flake.flakeModule
  ++ lib.optional (inputs ? devenv) inputs.devenv.flakeModule
  ++ lib.optional (inputs ? git-hooks) inputs.git-hooks.flakeModule;

  config = lib.mkMerge [
    # conditionally build process-compose if enabled
    (lib.mkIf (inputs ? process-compose-flake) {
      perSystem =
        { lib, ... }:
        {
          process-compose = lib.mkDefault { };
        };
    })

    # Validate: secrets.enable requires agenix input
    # This check runs at flake evaluation time
    (
      let
        secretsEnabled = config.stackpanel.secrets.enable;
        hasAgenix = inputs ? agenix;
        check =
          if secretsEnabled && !hasAgenix then
            throw ''
              stackpanel.secrets.enable requires agenix.

              Add to your flake inputs:
                agenix.url = "github:ryantm/agenix";
            ''
          else
            true;
      in
      # Force evaluation of check by using it in the condition
      lib.mkIf (secretsEnabled && check) { }
    )

    {
      perSystem =
        {
          system,
          pkgs,
          ...
        }:
        {
          # Make stackpanel's packages available to users
          # They can access: config.stackpanel.packages.cli
          _module.args.stackpanel = {
            inherit localFlake;
            # Access packages from the stackpanel flake itself
            packages = localFlake.withSystem system ({ config, ... }: config.packages or { });
          };
        };
    }
  ];
}
