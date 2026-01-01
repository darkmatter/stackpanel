# ==============================================================================
# caddy.nix
#
# Caddy reverse proxy module for devenv.
#
# This module provides a local Caddy server for development, enabling:
#   - Virtual hosts on .localhost domains
#   - Automatic HTTPS with Step CA integration
#   - Deterministic port assignment per project
#
# Commands provided:
#   caddy-start        - Start/reload caddy
#   caddy-stop         - Stop caddy
#   caddy-restart      - Restart caddy
#   caddy-status       - Check if caddy is running
#   caddy-add-site     - Add a virtual host
#   caddy-remove-site  - Remove a virtual host
#   caddy-list-sites   - List all configured sites
#   caddy-dev-site     - Quick setup for current project
#
# Usage:
#   stackpanel.caddy = {
#     enable = true;
#     project-name = "myapp";
#     use-step-tls = true;  # Optional: TLS via Step CA
#   };
# ==============================================================================
{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.stackpanel.caddy;
  stepCfg = config.stackpanel.network.step or {enable = false;};

  # Import util for debug logging
  util = import ../lib/util.nix { inherit pkgs lib config; };

  # Import shared caddy library
  caddyLib = import ../lib/services/caddy.nix {inherit pkgs lib;};

  # Compute project port if not explicitly set
  projectPort = if cfg.project-port != null
    then cfg.project-port
    else caddyLib.mkProjectPort { name = cfg.project-name; };

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
    port="''${2:-${toString projectPort}}"

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
  config = lib.mkIf cfg.enable {
    stackpanel.devshell.packages =
      caddyScripts.allPackages
      ++ [
        projectPortScript
        caddyDevSite
      ];

    stackpanel.devshell.hooks.after = lib.mkIf cfg.auto-start [
      ''
        # Start Caddy if not already running
        if ! ${caddyScripts.caddyStatus}/bin/caddy-status >/dev/null 2>&1; then
          ${util.log.debug "caddy: not running, starting..."}
          ${caddyScripts.caddyStart}/bin/caddy-start
          ${util.log.debug "caddy: started"}
        else
          ${util.log.debug "caddy: already running"}
        fi
      ''
    ];
  };
}
