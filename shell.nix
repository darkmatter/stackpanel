# ==============================================================================
# shell.nix
#
# Local development shell for the stackpanel repository.
# This file handles ALL local development concerns, keeping flake.nix clean.
#
# Usage:
#   nix develop --impure     # Uses devenv (default)
#   nix-shell                # Legacy nix-shell compatibility
#   direnv allow             # Automatic via .envrc
#
# This file:
#   - Imports local config from nix/internal/main.nix
#   - Decides between devenv and native shell based on config
#   - Sets up git hooks, packages, and shell environment
#
# flake.nix imports this to provide devShells.default
# ==============================================================================
{
  pkgs,
  lib,
  inputs,
  system,
  git-hooks ? null,
}:
let
  # Import merged config (single source of truth)
  mergedConfig = import ./nix/flake/merged-config.nix { inherit pkgs lib inputs; };

  # Extract sections
  stackpanelConfig = mergedConfig.stackpanel;
  devenvConfig = mergedConfig.devenv;
  gitHooksConfig = mergedConfig.git-hooks;

  # Check if devenv should be used
  useDevenv = stackpanelConfig.useDevenv or true;

  # Git hooks configuration (optional)
  pre-commit-check =
    if git-hooks != null then
      git-hooks.lib.${system}.run {
        src = ./.;
        hooks = builtins.removeAttrs gitHooksConfig [ "enable" ];
      }
    else
      null;

  # Module-based mkDevShell for native nix develop
  mkDevShell = import ./nix/flake/devshells/mkDevShell.nix { inherit pkgs; };

  # Local devshell config module (for devenv shells)
  # Pass merged config so it doesn't need to re-evaluate
  localDevshellModule = import ./nix/internal/devshell.nix { inherit inputs mergedConfig; };

  # Create a stackpanel-only module from main.nix config
  stackpanelOnlyModule =
    { ... }:
    {
      imports = [ ./nix/stackpanel/default.nix ];
      stackpanel = stackpanelConfig;
    };

  # Native devshell using module-based mkDevShell
  nativeDevshell = mkDevShell {
    modules = [ stackpanelOnlyModule ];
    specialArgs = { inherit inputs; };
  };
in
{
  # Export for use in flake.nix
  inherit
    useDevenv
    localDevshellModule
    nativeDevshell
    pre-commit-check
    stackpanelConfig
    devenvConfig
    gitHooksConfig
    ;

  # The default shell to use
  default = nativeDevshell;
}
