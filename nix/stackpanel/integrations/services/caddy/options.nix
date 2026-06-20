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
#   - tld: Top-level domain for virtual hosts (default: "localhost")
#
# Domain Format:
#   Virtual hosts use the format: <app>.<project>.<tld>
#   Example: web.myproject.localhost, api.myproject.lan
#
# Sites are registered via stackpanel.apps with domain configuration,
# or manually via stackpanel.globalServices.caddy.sites.
# ==============================================================================
{ lib, ... }:
{
  options.stackpanel.caddy = {
    enable = lib.mkEnableOption ''
      Caddy reverse proxy for stable local app domains and optional Step CA TLS.
    '';

    project-name = lib.mkOption {
      type = lib.types.str;
      default = "default";
      description = ''
        Project slug used to compute Caddy's stable admin/listener port and to
        form default app vhosts like <app>.<project>.<tld>.

        Keep this aligned with stackpanel.name or stackpanel.globalServices.project-name
        so generated sites remain consistent across machines.
      '';
      example = "stackpanel";
    };

    project-port = lib.mkOption {
      type = lib.types.nullOr lib.types.port;
      default = null;
      description = ''
        Stable Caddy port override. Leave null to compute the port from
        project-name; set only when integrating with existing local DNS or proxy
        conventions.
      '';
      example = 34521;
    };

    use-step-tls = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Use Step CA-issued certificates for local HTTPS sites.

        Requires the Stackpanel Step CA integration to be enabled and trusted by
        the host browser.
      '';
      example = true;
    };

    auto-start = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Start or reload Caddy automatically during devshell entry.

        Useful for teams that expect local domains to work immediately after
        direnv/nix develop activation.
      '';
      example = true;
    };

    tld = lib.mkOption {
      type = lib.types.str;
      default = "localhost";
      description = ''
        Top-level domain for virtual hosts.

        Virtual hosts use the format: <app>.<project>.<tld>
        For example, with project "myapp" and tld "localhost":
          - web app gets domain: web.myapp.localhost
          - api app gets domain: api.myapp.localhost

        Change to "lan" or "local" for custom DNS setups.
      '';
      example = "localhost";
    };
  };
}
