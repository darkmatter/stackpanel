# ==============================================================================
# native.nix
#
# Stackpanel flake-parts module for native Nix devShells (without devenv).
# Provides stackpanel options using pure Nix mkShell instead of devenv.
#
# Usage in user's flake.nix:
#
#   {
#     inputs = {
#       nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
#       flake-parts.url = "github:hercules-ci/flake-parts";
#       stackpanel.url = "github:darkmatter/stackpanel";
#     };
#
#     outputs = inputs@{ flake-parts, ... }:
#       flake-parts.lib.mkFlake { inherit inputs; } {
#         imports = [
#           inputs.stackpanel.flakeModules.native  # <-- this module
#         ];
#
#         systems = [ "x86_64-linux" "aarch64-darwin" ];
#
#         perSystem = { config, ... }: {
#           # Configure via stackpanel options
#           stackpanel = {
#             enable = true;
#             # your config here
#           };
#         };
#       };
#   }
#
# This creates devShells.default automatically from stackpanel config.
# ==============================================================================
# This uses the "importApply" pattern to get the localFlake reference.
{
  localFlake,
  withSystem,
}:
# The inner function is the actual flake-parts module.
{
  lib,
  flake-parts-lib,
  ...
}:
let
  inherit (flake-parts-lib) mkPerSystemOption;
  # Import mkShellFromConfig - takes already-evaluated config
  mkShellFromConfigFactory = import ../devshells/mkShellFromConfig.nix;

  # Get devenv-tasks-fast-build from stackpanel's devenv input
  # localFlake is stackpanel itself, which has devenv as an input
  stackpanelInputs = localFlake.inputs or { };
  hasDevenvInput = stackpanelInputs ? devenv;

  # Import full stackpanel module (options + config logic)
  stackpanelModule = ../../stackpanel/default.nix;
in
{
  # Use mkPerSystemOption to properly add options to perSystem
  # This is the correct flake-parts pattern for adding perSystem options
  options.perSystem = mkPerSystemOption (
    {
      config,
      pkgs,
      lib,
      system,
      inputs,
      ...
    }:
    {
      # Import full stackpanel (options + computed values)
      imports = [ stackpanelModule ];

      config =
        let
          cfg = config.stackpanel;

          # Create shell from already-evaluated config
          mkShellFromConfig = mkShellFromConfigFactory { inherit pkgs; };

          # Get devenv-tasks-fast-build from stackpanel's devenv input
          devenvTasksPkg =
            if hasDevenvInput && stackpanelInputs.devenv ? packages.${system}.devenv-tasks-fast-build then
              [ stackpanelInputs.devenv.packages.${system}.devenv-tasks-fast-build ]
            else
              [ ];

          # Build the shell directly from the evaluated devshell config
          # No need to re-evaluate modules - config.stackpanel.devshell already has everything
          nativeDevshell = mkShellFromConfig {
            devshellConfig = cfg.devshell;
            extraPackages = devenvTasksPkg;
          };
        in
        lib.mkIf (cfg.enable or false) {
          devShells.default = nativeDevshell;
        };
    }
  );
}
