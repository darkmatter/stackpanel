# ==============================================================================
# portless.nix
#
# Portless reverse proxy configuration options.
#
# Portless replaces port numbers with stable named `.localhost` URLs,
# eliminating the need to remember arbitrary port numbers for local services.
#
# Options:
#   - enable: Enable Portless reverse proxy
#   - project-name: Project name for URL namespacing
#   - tld: Top-level domain for virtual hosts (default: "localhost")
#   - use-https: Enable HTTPS with auto-generated self-signed certs
#   - tls-cert: Path to custom TLS certificate (e.g., from Step CA)
#   - tls-key: Path to custom TLS private key (e.g., from Step CA)
#   - auto-start: Automatically start the proxy on shell entry
#   - proxy-port: Override the proxy listen port
#
# Domain Format:
#   Virtual hosts use the format: <app>.<project>.<tld>
#   Example: web.myproject.localhost, api.myproject.test
#
# TLS supports Step CA certificates via --cert/--key passthrough.
#
# See https://port1355.dev/ for documentation.
# ==============================================================================
{lib, ...}: {
  options.stackpanel.portless = {
    enable = lib.mkEnableOption "Portless reverse proxy";

    project-name = lib.mkOption {
      type = lib.types.str;
      default = "default";
      description = "Project name used for URL namespacing. Apps are served at <app>.<project>.<tld> (e.g., web.myproject.localhost).";
      example = "myapp";
    };

    tld = lib.mkOption {
      type = lib.types.str;
      default = "localhost";
      description = ''
        Top-level domain for virtual hosts.

        Virtual hosts use the format: <app>.<project>.<tld>
        For example, with project "myapp" and tld "test":
          - web app gets domain: web.myapp.test
          - api app gets domain: api.myapp.test

        Recommended: "test" (IANA-reserved, no collision risk).
        Avoid "local" (conflicts with mDNS/Bonjour) and "dev" (Google-owned, forces HTTPS via HSTS).
        Default "localhost" requires no DNS configuration.

        Custom TLDs require sudo for /etc/hosts management.
      '';
      example = "test";
    };

    use-https = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable HTTPS with auto-generated self-signed certificates. For custom certs (e.g., Step CA), use tls-cert and tls-key instead.";
    };

    tls-cert = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Path to a TLS certificate file (e.g., from Step CA or mkcert). When set, implies HTTPS.";
      example = "/path/to/cert.pem";
    };

    tls-key = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Path to a TLS private key file (e.g., from Step CA or mkcert). When set, implies HTTPS.";
      example = "/path/to/key.pem";
    };

    auto-start = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Automatically start the Portless proxy when entering the shell.

        Defaults to true (unlike Caddy which defaulted to false) since
        Portless is lightweight and the proxy is needed for all URL routing.
      '';
    };

    proxy-port = lib.mkOption {
      type = lib.types.nullOr lib.types.port;
      default = null;
      description = ''
        Port the proxy listens on.

        Defaults to 1355 for HTTP or 443 for HTTPS when null.
        Only set this if you need to override the default.
      '';
      example = 8443;
    };
  };
}
