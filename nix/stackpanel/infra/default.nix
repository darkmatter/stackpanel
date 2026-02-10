# ==============================================================================
# infra/default.nix
#
# Infrastructure module system for stackpanel.
#
# This module provides a framework for infra modules (AWS, Fly, Cloudflare, etc.)
# that generates an alchemy-based IaC package with:
#   - A generated @stackpanel/infra library (Infra class)
#   - Pluggable output storage (SOPS, Chamber, SSM)
#   - Per-module TypeScript implementations
#   - An orchestrator (alchemy.run.ts) that imports modules and syncs outputs
#
# Usage:
#   stackpanel.infra = {
#     enable = true;
#     storage-backend = { type = "chamber"; chamber.service = "my-project"; };
#     aws.secrets.enable = true;
#   };
# ==============================================================================
{ ... }:
{
  imports = [
    ./options.nix
    ./codegen.nix
    ./modules/aws-secrets/module.nix
    ./modules/deployment/module.nix
  ];
}
