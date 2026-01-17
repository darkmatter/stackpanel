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
#
# Outputs provided:
#   - stackpanelConfig: Serializable config for agent/CLI access
#     Usage: nix eval --impure --json .#stackpanelConfig
# ==============================================================================
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
let
  # Helper to evaluate full stackpanel config from a config module
  # This evaluates the complete module system with user's config
  mkEvaluatedConfig =
    {
      pkgs,
      configModule,
    }:
    let
      evaluated = lib.evalModules {
        modules = [
          ../stackpanel
          configModule
        ];
        specialArgs = { inherit pkgs lib inputs; };
      };
    in
    evaluated.config.stackpanel;
in
{
  imports = [
    # Import stackpanel options (pkgs-free, safe for flake-parts top-level)
    ../stackpanel/core/options
  ]
  ++ lib.optional (inputs ? process-compose-flake) inputs.process-compose-flake.flakeModule
  ++ lib.optional (inputs ? devenv) inputs.devenv.flakeModule
  ++ lib.optional (inputs ? git-hooks) inputs.git-hooks.flakeModule;

  config = lib.mkMerge [
    # NOTE: stackpanelConfig and stackpanelFullConfig are NOT provided by this module.
    # Users should define them in their flake using the shell's passthru:
    #
    #   legacyPackages.stackpanelConfig = shell.passthru.stackpanelSerializable;
    #   legacyPackages.stackpanelFullConfig = shell.passthru.stackpanelConfig;
    #
    # Then in flake outputs:
    #   stackpanelConfig = withSystem "aarch64-darwin" ({ config, ... }: config.legacyPackages.stackpanelConfig);

    # Validate: secrets.enable requires agenix input
    # This check runs at flake evaluation time
    (
      let
        secretsEnabled = config.stackpanel.secrets.enable or false;
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

    # Base perSystem config - always applied
    {
      perSystem =
        {
          system,
          pkgs,
          lib,
          ...
        }:
        {
          # Make stackpanel's packages and helpers available to users
          _module.args.stackpanel = {
            inherit localFlake mkEvaluatedConfig;
            # Access packages from the stackpanel flake itself
            packages = withSystem system ({ config, ... }: config.packages or { });
          };
        };
    }

    # =========================================================================
    # Process-compose integration (optional, for process-compose-flake users)
    #
    # The `dev` command is built-in via stackpanel.process-compose.package.
    # This section only wires to process-compose-flake if users have it.
    # =========================================================================
    (lib.optionalAttrs (inputs ? process-compose-flake) (
      lib.mkIf (inputs ? process-compose-flake) {
        perSystem =
          {
            config,
            lib,
            ...
          }:
          let
            sp = config.legacyPackages.stackpanelFullConfig or null;
            pc = sp.process-compose or null;
            hasProcesses = pc != null && (pc.processes or { }) != { };
            enabled = pc != null && (pc.enable or false) && hasProcesses;
          in
          lib.mkIf enabled {
            # Wire to process-compose-flake for users who want its features
            process-compose.dev = {
              settings = {
                environment = pc.environment or { };
                processes = pc.processes;
              };
            };
          };
      }
    ))
  ];
}
