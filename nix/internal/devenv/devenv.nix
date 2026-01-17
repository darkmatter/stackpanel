# ==============================================================================
# devenv.nix
#
# Root devenv module for stackpanel's internal development environment.
# Aggregates all sub-modules for different parts of the stackpanel project.
#
# Imports:
#   - stackpanel core + all service modules (via flake devenv module pattern)
#   - web/devenv.nix     - Web app development (apps/web)
#   - docs/devenv.nix    - Documentation site development (apps/docs)
#   - docs/generate.nix  - Options documentation generator
#   - tools/devenv.nix   - Development tools and services (Postgres, Redis, etc.)
#
# This is imported by nix/internal/stackpanel.nix for local development.
# ==============================================================================
{ ... }:
{
  imports = [
    # # Import stackpanel core (options + core config)
    # ../../stackpanel/core
    # # Import service implementation modules (these add packages based on options)
    # ../../stackpanel/services/aws.nix
    # ../../stackpanel/services/caddy.nix
    # ../../stackpanel/services/global-services.nix
    # ../../stackpanel/network/network.nix
    # ../../stackpanel/network/ports.nix
    # ../../stackpanel/tui/default.nix
    # ../../stackpanel/ide/ide.nix
    # ../../stackpanel/apps/apps.nix
    # ../../stackpanel/core/cli.nix

    # App-specific modules for this project
    ./web/devenv.nix
    ./docs/devenv.nix
    # ./docs/generate.nix
    ./tools/devenv.nix
  ];

  cachix.enable = true;
  cachix.pull = [
    "stackpanel"
    "devenv"
    "darkmatter"
    "nix-community"
  ];
}
