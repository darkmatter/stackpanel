# ==============================================================================
# services/default.nix
#
# Development services module aggregator.
#
# This module imports all service-related devenv modules. Service implementations
# live in subdirectories (postgres/, redis/, minio/, caddy/) and are used by
# the modules imported here.
#
# Structure:
#   services/
#   ├── default.nix           # This file - imports all modules
#   ├── global-services.nix   # Maps globalServices to stackpanel.services
#   ├── postgres/default.nix  # PostgreSQL implementation
#   ├── redis/default.nix     # Redis implementation
#   ├── minio/default.nix     # MinIO implementation
#   ├── caddy/default.nix     # Caddy scripts library
#   ├── caddy.nix             # Caddy devenv module
#   ├── aws.nix               # AWS Roles Anywhere
#   ├── binary-cache.nix      # Nix binary cache
#   └── security-healthchecks.nix
#
# Usage:
#   # In devenv or flake module:
#   imports = [ ./services ];
# ==============================================================================
{ ... }:
{
  imports = [
    ./aws.nix
    ./binary-cache.nix
    ./caddy.nix
    ./global-services.nix
    ./security-healthchecks.nix
  ];
}
