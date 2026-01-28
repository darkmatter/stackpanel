# ==============================================================================
# dns.nix
#
# Local DNS configuration options for development.
#
# Configures how local domain names (e.g., myapp.localhost) are resolved.
# Supports multiple backends:
#   - caddy: Use Caddy's built-in DNS and reverse proxy (default)
#   - apple-container: Use Apple's container DNS system (macOS only)
#   - manual: No automatic DNS configuration
#
# Apple Container DNS:
#   Uses `container system dns create <domain> --localhost <ip>` to register
#   local domains. This integrates with Apple's container tool and provides
#   native macOS DNS resolution without /etc/hosts modifications.
#
# Usage:
#   stackpanel.dns = {
#     backend = "apple-container";  # or "caddy" (default)
#     domains = [ "myapp.localhost" "api.localhost" ];
#   };
# ==============================================================================
{ lib, ... }:
{
  options.stackpanel.dns = {
    enable = lib.mkEnableOption "local DNS configuration" // { default = true; };

    backend = lib.mkOption {
      type = lib.types.enum [
        "caddy"
        "apple-container"
        "manual"
      ];
      default = "caddy";
      description = ''
        DNS backend for local development domains.

        - caddy: Use Caddy reverse proxy (handles both DNS-like routing and TLS)
        - apple-container: Use Apple's container DNS system (macOS only)
          Runs: sudo container system dns create <domain> --localhost <ip>
        - manual: No automatic DNS configuration (user manages /etc/hosts)
      '';
    };

    localhost-ip = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = ''
        IP address for localhost DNS entries.
        
        For Apple container DNS, you may want to use a specific IP like
        203.0.113.113 to avoid conflicts. The container tool will route
        this to localhost automatically.
      '';
      example = "203.0.113.113";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "host.container.internal";
      description = ''
        The host domain for Apple container DNS.
        This is the base domain that containers use to reach the host.
      '';
    };

    domains = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Additional domains to register with the DNS backend.
        App domains are automatically included based on stackpanel.apps configuration.
      '';
      example = [ "api.localhost" "dashboard.localhost" ];
    };

    auto-setup = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Automatically configure DNS on shell entry.
        For apple-container backend, this runs the DNS setup commands.
      '';
    };
  };
}
