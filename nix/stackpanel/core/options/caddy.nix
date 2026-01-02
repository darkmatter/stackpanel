# ==============================================================================
# caddy.nix
#
# Caddy reverse proxy configuration options.
#
# Configures a global Caddy instance for reverse proxying development servers.
# Caddy provides automatic HTTPS with Step CA integration for local development.
#
# Options:
#   - enable: Enable Caddy reverse proxy
#   - project-name: Project name for stable port computation
#   - project-port: Override computed port (optional)
#   - use-step-tls: Use Step CA for TLS certificates
#   - auto-start: Automatically start Caddy when entering the shell
#
# Sites are registered via stackpanel.apps with domain configuration,
# or manually via stackpanel.globalServices.caddy.sites.
# ==============================================================================
{ lib, ... }:
{
  options.stackpanel.caddy = {
    enable = lib.mkEnableOption "Caddy reverse proxy";

    project-name = lib.mkOption {
      type = lib.types.str;
      default = "default";
      description = "Project name used to compute a stable port. Set this to your project name for consistent port allocation.";
      example = "myapp";
    };

    project-port = lib.mkOption {
      type = lib.types.nullOr lib.types.port;
      default = null;
      description = "Stable port for Caddy. If null, computed from project-name.";
      example = 34521;
    };

    use-step-tls = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Use Step CA for TLS certificates (requires stackpanel.network.step.enable)";
    };

    auto-start = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Automatically start Caddy when entering the shell";
    };
  };
}
