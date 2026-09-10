# ==============================================================================
# packages.nix
#
# Package definitions for stackpanel.
# Defines the unified CLI/agent package built by this flake.
#
# The CLI and agent have been merged into a single application at apps/stackpanel-go.
# The agent is now a subcommand: `stack agent`
# ==============================================================================
{
  pkgs,
  flake ? null,
}:
let
  # Unified CLI + Agent package
  stackpanel = pkgs.callPackage ../stackpanel/packages/stackpanel-cli { inherit flake; };
in
{
  # Main stackpanel package (CLI + agent unified)
  inherit stackpanel;

  # Alias for backwards compatibility
  stackpanel-cli = stackpanel;

  # Default package
  default = stackpanel;
}
