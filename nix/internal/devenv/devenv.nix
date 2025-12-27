# ==============================================================================
# devenv.nix
#
# Root devenv module for stackpanel's internal development environment.
# Aggregates all sub-modules for different parts of the stackpanel project.
#
# Imports:
#   - web/devenv.nix     - Web app development (apps/web)
#   - docs/devenv.nix    - Documentation site development (apps/docs)
#   - docs/generate.nix  - Options documentation generator
#   - tools/devenv.nix   - Development tools and services (Postgres, Redis, etc.)
#
# This is imported by nix/internal/stackpanel.nix for local development.
# ==============================================================================

{...}: {
  imports = [
    ./web/devenv.nix
    ./docs/devenv.nix
    ./docs/generate.nix
    ./tools/devenv.nix
  ];
}