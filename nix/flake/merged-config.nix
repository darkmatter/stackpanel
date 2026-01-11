# ==============================================================================
# merged-config.nix
#
# Single source of truth for configuration that merges:
#   1. .stackpanel/config.nix (user configuration)
#   2. nix/stackpanel (option definitions)
#   3. nix/internal/* (ONLY for configuration, NOT devshell.nix)
#
# Returns: { stackpanel = {...}; devenv = {...}; git-hooks = {...}; }
#
# This file:
#   - Evaluates stackpanel modules to get validated config
#   - Extracts devenv config directly from .stackpanel/config.nix
#   - Provides clean separation between stackpanel and devenv
# ==============================================================================
{
  pkgs,
  lib,
  inputs,
}:
let
  # Import serialization helpers
  serializeLib = import ../../nix/stackpanel/lib/serialize.nix { inherit lib; };

  # Import stackpanel config from .stackpanel/config.nix
  # Returns { stackpanel = {...}; }
  stackpanelConfigModule = import ../../.stackpanel/config.nix;

  # Import devenv and git-hooks config from .stackpanel/devenv.nix
  # Returns { packages = [...]; languages = {...}; env = {...}; git-hooks = {...}; }
  devenvConfigData = import ../../.stackpanel/devenv.nix { inherit pkgs lib inputs; };

  # Separate devenv and git-hooks
  devenvConfig = builtins.removeAttrs devenvConfigData [ "git-hooks" ];
  gitHooksConfig =
    if stackpanelConfigModule ? stackpanel && stackpanelConfigModule.stackpanel ? git-hooks then
      stackpanelConfigModule.stackpanel.git-hooks
    else
      devenvConfigData.git-hooks or { };

  # Evaluate stackpanel modules with user config
  # This validates stackpanel config and computes derived values
  stackpanelEval = lib.evalModules {
    modules = [
      ../../nix/stackpanel
      stackpanelConfigModule
    ];
    specialArgs = { inherit pkgs lib inputs; };
  };

  # Extract validated and computed stackpanel config
  stackpanelConfig = stackpanelEval.config.stackpanel;

  # Create a JSON-safe version by filtering out non-serializable values
  # (derivations, functions, paths, internal module system attributes)
  stackpanelSerializableConfig = serializeLib.filterSerializable stackpanelConfig;
in
{
  # Stackpanel config (validated and computed via module system)
  # May contain non-serializable values (derivations, functions, etc.)
  stackpanel = stackpanelConfig;

  # JSON-safe version of stackpanel config
  # All non-serializable values are filtered out
  stackpanelSerializable = stackpanelSerializableConfig;

  # Raw config module (for native shell that needs to evaluate modules itself)
  stackpanelConfigModule = stackpanelConfigModule;

  # Devenv config (passed through without validation)
  devenv = devenvConfig;

  # Git hooks config (passed through without validation)
  git-hooks = gitHooksConfig;
}
