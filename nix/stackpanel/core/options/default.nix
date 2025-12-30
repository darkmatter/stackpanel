# ==============================================================================
# default.nix
#
# Options module index - aggregates all Stackpanel option definitions.
#
# This module imports all option definition files from the options/ directory,
# providing a single entry point for the complete Stackpanel configuration schema.
#
# Each option file defines a specific feature area:
#   - core.nix: Root paths, directories, and basic settings
#   - apps.nix: Application port and domain configuration
#   - ports.nix: Deterministic port computation
#   - devshell.nix: Shell environment (packages, hooks, commands)
#   - And more...
#
# Imported by: ../default.nix
# ==============================================================================
{ ... }:
{
  imports = [
    ./apps.nix
    ./aws.nix
    ./caddy.nix
    ./ci.nix
    ./cli.nix
    ./codegen.nix
    ./core.nix
    ./devshell.nix
    ./global-services.nix
    ./ide.nix
    ./motd.nix
    ./step-ca.nix
    ./ports.nix
    ./secrets.nix
    ./theme.nix
  ];
}
