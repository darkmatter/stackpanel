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
  # Import stackpanel config from .stackpanel/config.nix
  # Returns { stackpanel = {...}; }
  stackpanelConfigModule = import ../../.stackpanel/config.nix;

  # Import devenv and git-hooks config from .stackpanel/devenv.nix
  # Returns { packages = [...]; languages = {...}; env = {...}; git-hooks = {...}; }
  devenvConfigData = import ../../.stackpanel/devenv.nix { inherit pkgs lib inputs; };

  # Separate devenv and git-hooks
  devenvConfig = builtins.removeAttrs devenvConfigData ["git-hooks"];
  gitHooksConfig = devenvConfigData.git-hooks or {};

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

in {
  # Stackpanel config (validated and computed via module system)
  stackpanel = stackpanelConfig;
  
  # Devenv config (passed through without validation)
  devenv = devenvConfig;
  
  # Git hooks config (passed through without validation)
  git-hooks = gitHooksConfig;
}
