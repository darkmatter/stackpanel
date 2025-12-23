# Caddy reverse proxy for devenv
#
# Usage in devenv.nix:
#   stackpanel.caddy = {
#     enable = true;
#     projectName = "myapp";  # Used to compute stable port
#     # Optional: integrate with Step CA for TLS
#     useStepTls = true;
#   };
#
# Access the computed port:
#   config.stackpanel.caddy.project-port  # e.g., 34521
#
# Commands:
#   caddy-start        # Start/reload caddy
#   caddy-stop         # Stop caddy
#   caddy-restart      # Restart caddy
#   caddy-status       # Check if caddy is running
#   caddy-add-site     # Add a virtual host
#   caddy-remove-site  # Remove a virtual host
#   caddy-list-sites   # List all configured sites
#   caddy-project-port # Get stable port for current directory
#
{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.stackpanel.caddy;
  stepCfg = config.stackpanel.network.step or {enable = false;};

  # Import shared caddy library
  caddyLib = import ../lib/caddy.nix {inherit pkgs lib;};

  # Create scripts using shared library
  caddyScripts = caddyLib.mkCaddyScripts {
    stepEnabled = cfg.use-step-tls && stepCfg.enable;
    stepCaUrl = stepCfg.ca-url or "";
    stepCaFingerprint = stepCfg.ca-fingerprint or "";
  };

  # Get stable project port for current directory
  projectPortScript = pkgs.writeShellScriptBin "project-port" ''
    ${caddyScripts.caddyProjectPort}/bin/caddy-project-port "$@"
  '';

  # Helper script to quickly set up a dev site for the current project
  caddyDevSite = pkgs.writeShellScriptBin "caddy-dev-site" ''
    set -euo pipefail

    project_name="''${1:-${cfg.project-name}}"
    port="''${2:-${toString cfg.project-port}}"

    domain="$project_name.localhost"
    upstream="localhost:$port"

    echo "Setting up dev site:"
    echo "  Domain:   $domain"
    echo "  Upstream: $upstream"
    echo "  Port:     $port"
    echo ""

    ${caddyScripts.caddyAddSite}/bin/caddy-add-site "$domain" "$upstream"

    # Start/reload caddy
    ${caddyScripts.caddyStart}/bin/caddy-start

    echo ""
    echo "Your dev site is available at: http://$domain"
    echo "Start your dev server on port $port"
  '';
in {
  options.stackpanel.caddy = {
    enable = lib.mkEnableOption "Caddy reverse proxy";

    project-name = lib.mkOption {
      type = lib.types.str;
      default = "default";
      description = "Project name used to compute a stable port. Set this to your project name for consistent port allocation.";
      example = "myapp";
    };

    project-port = lib.mkOption {
      type = lib.types.port;
      default = caddyLib.mkProjectPort {name = cfg.project-name;};
      defaultText = lib.literalExpression "caddyLib.mkProjectPort { name = cfg.project-name; }";
      description = "Computed stable port based on project-name. Can be overridden manually.";
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

  config = lib.mkIf cfg.enable {
    packages =
      caddyScripts.allPackages
      ++ [
        projectPortScript
        caddyDevSite
      ];

    enterShell = lib.mkIf cfg.auto-start ''
      # Start Caddy if not already running
      if ! ${caddyScripts.caddyStatus}/bin/caddy-status >/dev/null 2>&1; then
        ${caddyScripts.caddyStart}/bin/caddy-start
      fi
    '';
  };
}
