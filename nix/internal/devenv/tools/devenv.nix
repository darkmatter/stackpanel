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
  # Define apps with ports and optional Caddy vhosts
  # Each app gets:
  #   - A deterministic port (basePort + offset)
  #   - Environment variable: PORT_<NAME>
  #   - Optional: Caddy vhost at <domain>.localhost
  #
  # Access in shell: $PORT_WEB, $URL_WEB
  stackpanel.apps = {
    web = {domain = "stackpanel";}; # -> stackpanel.localhost:6400
    server = {}; # -> port 6401 (no vhost)
    docs = {domain = "docs";}; # -> docs.localhost:6402
  };

  # Define infrastructure services with ports
  # Each service gets:
  #   - A deterministic port (basePort + 10 + index)
  #   - Environment variable: STACKPANEL_<KEY>_PORT
  #
  # Access in Nix: config.stackpanel.ports.service.POSTGRES.port
  # Access in shell: $STACKPANEL_POSTGRES_PORT
  stackpanel.ports.services = [
    {
      key = "POSTGRES";
      name = "PostgreSQL";
    }
    {
      key = "REDIS";
      name = "Redis";
    }
    {
      key = "MINIO";
      name = "Minio";
    }
    {
      key = "MINIO_CONSOLE";
      name = "Minio Console";
    }
  ];

  # Enable project-local services (data stored in .stackpanel/state/services/)
  # Ports are automatically computed from project-name (see stackpanel.ports)
  stackpanel.globalServices = {
    enable = true;
    project-name = "stackpanel";

    # PostgreSQL for local development
    postgres = {
      enable = true;
      databases = ["stackpanel" "stackpanel_test"];
      package = pkgs.postgresql_17;
    };

    # Redis for caching
    redis.enable = true;

    # Minio for S3-compatible storage
    minio.enable = true;

    # Caddy reverse proxy (uses ~/.config/caddy/sites.d/)
    caddy.enable = true;
  };

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
