# ==============================================================================
# dns.nix
#
# Local DNS module implementation for development environments.
#
# Implements DNS backends:
#   - apple-container: Uses Apple's container DNS system
#   - caddy: Relies on Caddy for routing (no separate DNS config)
#   - manual: No automatic configuration
#
# Apple Container DNS:
#   The container tool provides a lightweight macOS-native way to run
#   Linux containers. It includes a DNS system that can register domains
#   pointing to localhost, which containers can then use to reach the host.
#
#   Command: sudo container system dns create <domain> --localhost <ip>
#
# This module adds:
#   - Shell scripts for DNS management (dns-setup, dns-status, dns-remove)
#   - Shell hook for automatic DNS configuration on shell entry
#   - MOTD entries for DNS status
# ==============================================================================
{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.stackpanel.dns;
  appsCfg = config.stackpanel.apps or { };

  # Collect all domains from apps that have a domain configured
  appDomains = lib.pipe appsCfg [
    (lib.filterAttrs (_: app: (app.domain or null) != null))
    (lib.mapAttrsToList (_: app: app.domain))
  ];

  # All domains to configure
  allDomains = lib.unique (cfg.domains ++ appDomains);

  # Apple container DNS setup script
  appleContainerDnsSetup = pkgs.writeShellScriptBin "dns-setup" ''
    set -euo pipefail

    if [[ "$(uname)" != "Darwin" ]]; then
      echo "❌ Apple container DNS is only available on macOS"
      exit 1
    fi

    if ! command -v container &> /dev/null; then
      echo "❌ Apple container tool not installed"
      echo ""
      echo "Install with: container-install"
      exit 1
    fi

    HOST="${cfg.host}"
    IP="${cfg.localhost-ip}"
    DOMAINS=(${lib.concatStringsSep " " (map (d: ''"${d}"'') allDomains)})

    echo "🌐 Setting up Apple container DNS..."
    echo "   Host: $HOST"
    echo "   IP: $IP"
    echo ""

    # Ensure container system is running
    if ! container system status &> /dev/null; then
      echo "📦 Starting container system..."
      container system start
    fi

    # Create the main host entry
    echo "➕ Creating DNS entry: $HOST -> $IP"
    sudo container system dns create "$HOST" --localhost "$IP" 2>/dev/null || \
      echo "   (already exists or updated)"

    # Create entries for each app domain
    for domain in "''${DOMAINS[@]}"; do
      if [[ -n "$domain" ]]; then
        echo "➕ Creating DNS entry: $domain -> $IP"
        sudo container system dns create "$domain" --localhost "$IP" 2>/dev/null || \
          echo "   (already exists or updated)"
      fi
    done

    echo ""
    echo "✅ DNS configured! Containers can now reach:"
    echo "   - $HOST"
    for domain in "''${DOMAINS[@]}"; do
      [[ -n "$domain" ]] && echo "   - $domain"
    done
  '';

  # DNS status script
  appleContainerDnsStatus = pkgs.writeShellScriptBin "dns-status" ''
    set -euo pipefail

    if [[ "$(uname)" != "Darwin" ]]; then
      echo "❌ Apple container DNS is only available on macOS"
      exit 1
    fi

    if ! command -v container &> /dev/null; then
      echo "❌ Apple container tool not installed"
      exit 1
    fi

    echo "🌐 Apple Container DNS Status"
    echo ""

    if container system status &> /dev/null; then
      echo "✅ Container system is running"
    else
      echo "❌ Container system is not running"
      echo "   Run: container system start"
      exit 1
    fi

    echo ""
    echo "DNS entries:"
    container system dns list 2>/dev/null || echo "   (none configured)"
  '';

  # DNS remove script
  appleContainerDnsRemove = pkgs.writeShellScriptBin "dns-remove" ''
    set -euo pipefail

    if [[ "$(uname)" != "Darwin" ]]; then
      echo "❌ Apple container DNS is only available on macOS"
      exit 1
    fi

    if ! command -v container &> /dev/null; then
      echo "❌ Apple container tool not installed"
      exit 1
    fi

    HOST="${cfg.host}"
    DOMAINS=(${lib.concatStringsSep " " (map (d: ''"${d}"'') allDomains)})

    echo "🌐 Removing Apple container DNS entries..."

    # Remove entries
    for domain in "$HOST" "''${DOMAINS[@]}"; do
      if [[ -n "$domain" ]]; then
        echo "➖ Removing: $domain"
        sudo container system dns remove "$domain" 2>/dev/null || true
      fi
    done

    echo ""
    echo "✅ DNS entries removed"
  '';

  # Determine which packages to include based on backend
  dnsPackages =
    if cfg.backend == "apple-container" then
      [
        appleContainerDnsSetup
        appleContainerDnsStatus
        appleContainerDnsRemove
      ]
    else
      [ ];

  # Shell hook for auto-setup
  dnsAutoSetupHook =
    if cfg.backend == "apple-container" && cfg.auto-setup then
      ''
        # Auto-setup Apple container DNS (if available)
        if [[ "$(uname)" == "Darwin" ]] && command -v container &> /dev/null; then
          if container system status &> /dev/null 2>&1; then
            # Silently ensure DNS is configured
            ${appleContainerDnsSetup}/bin/dns-setup > /dev/null 2>&1 || true
          fi
        fi
      ''
    else
      "";

in
{
  config = lib.mkIf (cfg.enable && cfg.backend == "apple-container") {
    stackpanel.devshell.packages = dnsPackages;

    stackpanel.devshell.hooks.main = lib.mkIf cfg.auto-setup [ dnsAutoSetupHook ];

    stackpanel.motd.commands = [
      {
        name = "dns-setup";
        description = "Configure Apple container DNS";
      }
      {
        name = "dns-status";
        description = "Show DNS status";
      }
      {
        name = "dns-remove";
        description = "Remove DNS entries";
      }
    ];

    stackpanel.motd.features = [ "Apple Container DNS (${cfg.host})" ];

    # Add scripts for all backends
    stackpanel.scripts = {
      dns-setup = {
        description = "Configure local DNS for development";
        exec = ''
          ${appleContainerDnsSetup}/bin/dns-setup "$@"
        '';
      };

      dns-status = {
        description = "Show local DNS status";
        exec = ''
          ${appleContainerDnsStatus}/bin/dns-status "$@"
        '';
      };

      dns-remove = {
        description = "Remove local DNS entries";
        exec = ''
          ${appleContainerDnsRemove}/bin/dns-remove "$@"
        '';
      };
    };
  };
}
