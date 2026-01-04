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
{
  localFlake,
  withSystem,
  devshell,
}:
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
  imports =
    lib.optional (inputs ? process-compose-flake) inputs.process-compose-flake.flakeModule
    ++ lib.optional (inputs ? devenv) inputs.devenv.flakeModule
    ++ lib.optional (inputs ? git-hooks) inputs.git-hooks.flakeModule;

  config = lib.mkMerge [
    (lib.mkIf (inputs ? process-compose-flake) {
      perSystem =
        { lib, ... }:
        {
          process-compose = lib.mkDefault { };
        };
    })
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
            packages = withSystem system ({ config, ... }: config.packages or { });
          };
        };
    }
  ];

  # This flake module doesn't need to define any flake-parts options.
  # All the real work is done by the devenv module (devenvModules.default).
  #
  # However, we could add flake-level options here if needed, for example:
  #
  # options.flake = {
  #   stackpanel = {
  #     someFlakeLevelOption = lib.mkOption { ... };
  #   };
  # };

  # Provide a way for perSystem to access the stackpanel flake's packages
  # This is useful for things like the stackpanel CLI
  # perSystem is now defined under config to avoid top-level/config mixing.
}
