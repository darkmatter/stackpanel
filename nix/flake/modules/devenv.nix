# ==============================================================================
# devenv.nix - Devenv Adapter
#
# Bridges stackpanel's module system with devenv's native configuration.
# This is the ONLY file that has devenv-specific knowledge.
#
# Import flow:
#   User's devenv config
#     → this adapter
#       → nix/stackpanel/default.nix (core module system, devenv-agnostic)
#
# Mappings:
#   config.stackpanel.devshell.packages    → devenv packages (includes scripts package)
#   config.stackpanel.devshell.env         → devenv env
#   config.stackpanel.devshell.hooks.*     → devenv enterShell (before/main/after phases)
#   config.stackpanel.scripts              → scripts package in devshell
#   config.stackpanel.outputs              → devenv outputs
#
# Scripts are handled by nix/stackpanel/devshell/scripts.nix which creates a
# single package containing all scripts in bin/. This package is automatically
# added to devshell.packages when scriptsConfig.enable is true (default).
#
# Containers:
#   Currently handled directly by stackpanel's containers module using
#   dockerTools.buildImage. Devenv's nix2container integration is available
#   but disabled due to package name conflicts and upstream issues with
#   skopeo-nix2container. To re-enable devenv containers passthrough,
#   uncomment the `containers = devenvContainers;` line below.
#
# Usage in flake-parts:
#   devenv.shells.default = {
#     imports = [ inputs.stackpanel.devenvModules.default ];
#     stackpanel.enable = true;
#     stackpanel.theme.enable = true;
#   };
# ==============================================================================
{
  config,
  lib,
  ...
}:
let
  hooks = config.stackpanel.hooks or config.stackpanel.devshell.hooks;

  enterShell = lib.concatStringsSep "\n\n" (
    lib.flatten [
      hooks.before
      hooks.main
      hooks.after
    ]
  );

  # Note: stackpanel.tasks are for Turborepo integration, not devenv tasks.
  # Devenv tasks have a different schema (exec, before, after).
  # If you need devenv-specific tasks, define them directly in your devenv.nix.

  # Outputs from stackpanel.outputs
  outputs = config.stackpanel.outputs or { };

  # ---------------------------------------------------------------------------
  # Container configuration passthrough (DISABLED - see header comment)
  # Maps stackpanel.containers to devenv.containers format for nix2container
  #
  # KNOWN ISSUES:
  # 1. Package name conflicts: Both stackpanel and devenv expose container-*
  #    packages, causing "defined multiple times" errors
  # 2. skopeo-nix2container build failure: upstream nix2container flake has
  #    a broken skopeo derivation that fails with missing vendor directory
  # ---------------------------------------------------------------------------
  stackpanelContainers = config.stackpanel.containers or { };

  # Transform stackpanel container config to devenv format
  # Only include non-null/non-empty values to let devenv use its defaults
  # Key: devenv defaults copyToRoot to `self` (project root) which is what we want
  mkDevenvContainer =
    name: containerCfg:
    lib.filterAttrs (_: v: v != null) {
      inherit (containerCfg) name version;
      # copyToRoot: only set if explicitly configured, otherwise devenv uses `self`
      copyToRoot = containerCfg.copyToRoot;
      startupCommand = containerCfg.startupCommand;
      entrypoint = containerCfg.entrypoint;
      workingDir = containerCfg.workingDir;
      registry = containerCfg.registry;
      defaultCopyArgs = if containerCfg.defaultCopyArgs == [ ] then null else containerCfg.defaultCopyArgs;
      maxLayers = containerCfg.maxLayers;
      layers = if containerCfg.layers == [ ] then null else containerCfg.layers;
    };

  devenvContainers = lib.mapAttrs mkDevenvContainer stackpanelContainers;
in
{
  # Single entrypoint - imports all stackpanel modules
  # Features only activate when their .enable option is set
  # Note: devenv provides pkgs via its module system
  imports = [
    ../../stackpanel
  ];

  config = {
    packages = config.stackpanel.devshell.packages;
    env = config.stackpanel.devshell.env;
    enterShell = enterShell;

    # ---------------------------------------------------------------------------
    # Devenv containers passthrough (DISABLED)
    #
    # Uncomment below to use devenv's nix2container integration instead of
    # stackpanel's dockerTools implementation. This requires:
    # 1. Fix for skopeo-nix2container upstream
    # 2. Disable stackpanel's container packages to avoid conflicts
    #
    # When enabled, use: devenv container copy <name>
    # ---------------------------------------------------------------------------
    # containers = devenvContainers;

    outputs = outputs;
  };
}
