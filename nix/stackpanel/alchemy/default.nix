# ==============================================================================
# alchemy/default.nix
#
# Lower-level primitive module for Alchemy IaC configuration.
#
# Provides centralized alchemy SDK configuration consumed by other modules
# (infra/, deployment/, etc.):
#   - Alchemy version management
#   - State store configuration (Cloudflare, filesystem, auto)
#   - A generated shared TypeScript package (@gen/alchemy) with:
#     - createApp() factory function
#     - State store provider
#     - Shared helpers (SSM reads, secret wrapping, binding resolution)
#   - ALCHEMY_STATE_TOKEN secret management
#   - .gitignore for .alchemy directories
#
# Usage:
#   stackpanel.alchemy = {
#     enable = true;
#     stateStore.provider = "auto";
#   };
#
# Other modules consume this via:
#   config.stackpanel.alchemy.version      (npm version)
#   config.stackpanel.alchemy.package.*    (generated package config)
#   config.stackpanel.alchemy.deploy.*     (setup + deploy scripts)
#   @gen/alchemy                          (TypeScript import)
# ==============================================================================
{ ... }:
{
  imports = [
    ./options.nix
    ./codegen.nix
  ];
}
