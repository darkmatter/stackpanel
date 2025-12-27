# ==============================================================================
# defaults.nix
#
# Opinionated default configuration for devshell environments.
#
# This module sets sensible defaults that are applied to all stackpanel
# devshells, including common packages (git, jq) and a shell entry message.
# These can be overridden in project-specific configuration.
# ==============================================================================
{ lib, pkgs, ... }:
{
  config = {
    stackpanel.devshell.packages = [ pkgs.git pkgs.jq ];
    stackpanel.devshell.hooks.before = lib.mkBefore [ ''echo "stackpanel shell"'' ];
  };
}