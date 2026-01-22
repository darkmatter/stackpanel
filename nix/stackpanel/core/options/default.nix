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
# The db schema (.proto.nix files) is the source of truth for data types.
# Option files that need proto-derived types import db directly.
#
# Imported by: ../default.nix
# ==============================================================================
{ ... }:
{
  imports = [
    ./apps.nix
    ./aws.nix
    ./binary-cache.nix
    ./caddy.nix
    ./ci.nix
    ./cli.nix
    ./codegen.nix
    ./core.nix
    ./devshell.nix
    ./extensions.nix
    ./global-services.nix
    ./healthchecks.nix
    ./ide.nix
    ./motd.nix
    ./outputs.nix
    ./panels.nix
    ./step-ca.nix
    ./state.nix
    ./tasks.nix
    ./ports.nix
    ./secrets.nix
    ./theme.nix
    ./user-packages.nix
    ./users.nix
    ./variables.nix
  ];
}
