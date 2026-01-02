# ==============================================================================
# tools/devenv.nix
#
# Development infrastructure services for the stackpanel project.
# Configures local services like PostgreSQL, Redis, Minio, and Caddy.
#
# Services are PROJECT-LOCAL by default, stored in .stackpanel/state/services/
# allowing different projects to use different versions of databases.
# Exception: Caddy is GLOBAL (shared across projects) to avoid port 443 conflicts.
#
# Port allocation:
#   - Apps: basePort + 0-9 (web, server, docs)
#   - Services: basePort + 10+ (postgres, redis, minio)
#
# CLI commands: stackpanel status, stackpanel services start/stop
# ==============================================================================

# Stackpanel-specific devenv services
#
# This file contains service configurations specific to developing stackpanel.
#
# Services are PROJECT-LOCAL by default, stored in:
#   .stackpanel/state/services/
#
# This allows different projects to use different versions of PostgreSQL, etc.
#
# Exception: Caddy is GLOBAL (shared across all projects) to avoid port 443 conflicts.
# Caddy config: ~/.config/caddy/sites.d/
# Project symlinks: .stackpanel/caddy/ -> global config (for easy access/customization)
#
# Ports are automatically computed from projectName:
#   - Apps: basePort + 0-9 (web, server, docs)
#   - Services: basePort + 10+ (postgres, redis, minio)
#
# CLI Commands (via 'stackpanel' binary):
#   stackpanel status             - Show all service status
#   stackpanel services start     - Start all services
#   stackpanel services stop      - Stop all services
#   stackpanel caddy add <d> <u>  - Add a Caddy site (creates symlink in project)
#
{
  pkgs,
  lib,
  config,
  ...
}: {
  # NOTE: stackpanel.* options have been moved to .stackpanel/config.nix
  # This file should only contain devenv-native options.
  #
  # The stackpanel configuration is evaluated separately and its outputs
  # (packages, env, hooks) are passed to devenv without importing the
  # stackpanel module system into devenv.
  #
  # See .stackpanel/config.nix for:
  #   - stackpanel.apps (web, server, docs)
  #   - stackpanel.ports.services (postgres, redis, minio)
  #   - stackpanel.globalServices (postgres, redis, minio, caddy)

  # Mailpit for email testing (UI on port 8025)
  # Keep this as devenv service since it's lightweight and project-specific
  services.mailpit = {
    enable = true;
  };

  # Tailscale funnel for sharing dev server
  # services.tailscale.funnel.enable = true;
  # services.tailscale.funnel.target = "localhost:8443";

  # Profile for sharing server with team
  profiles.share = {
    module = {
      services.tailscale.funnel.enable = true;
      services.tailscale.funnel.target = "localhost:3000";
    };
  };
}
