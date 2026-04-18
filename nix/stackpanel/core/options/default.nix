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
{...}: {
  imports = [
    ./apps.nix
    # aws.nix -- colocated into services/aws/options.nix
    # binary-cache.nix -- colocated into services/binary-cache.nix
    # caddy.nix -- colocated into services/caddy/options.nix
    ./checks.nix
    # ci.nix -- colocated into apps/ci.nix
    ./cli.nix
    # codegen.nix -- colocated into modules/env-codegen/options.nix
    ./core.nix
    ./devshell.nix
    # dns.nix -- colocated into network/dns.nix
    ./envs.nix
    # extensions.nix -- flattened into core/extensions.nix
    # global-services.nix -- colocated into services/global-services-options.nix
    ./healthchecks.nix
    # ide.nix -- colocated into ide/options.nix
    ./modules.nix
    # motd.nix -- colocated into devshell/motd-options.nix
    ./outputs.nix
    ./panels.nix
    # portless.nix -- colocated into network/portless-options.nix
    # step-ca.nix -- colocated into network/step-ca-options.nix
    ./state.nix
    # tasks.nix -- flattened into core/tasks.nix
    # ports.nix -- colocated into network/ports-options.nix
    ./secrets.nix
    # services.nix -- colocated into services/services-options.nix
    # theme.nix -- colocated into tui/theme.nix
    ./user-packages.nix
    # users.nix -- flattened into core/users-options.nix
    ./variables.nix
    ./variables-backend.nix
  ];
}
