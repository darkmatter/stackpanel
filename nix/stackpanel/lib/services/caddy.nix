# ==============================================================================
# services/caddy.nix
#
# Caddy reverse proxy utilities - pure functions for managing Caddy configuration.
# Works with any Nix module system (flake-parts, devenv, NixOS, etc.)
#
# Provides scripts for Caddy lifecycle management, site configuration, and
# integration with Step CA for automatic TLS certificates.
#
# Features:
#   - Stable port computation from project name (mkProjectPort)
#   - Site registration and configuration management
#   - Step CA TLS integration for local HTTPS
#   - Caddyfile generation with import-based site organization
#   - Start/stop/reload/status scripts
#
# All paths use $HOME at runtime for purity - no builtins.getEnv needed.
# Override with CADDY_CONFIG_DIR environment variable if needed.
#
# Usage:
#   let caddyLib = import ./caddy.nix { inherit pkgs lib; };
#   in caddyLib.mkCaddyScripts { stepEnabled = true; stepCaUrl = "..."; }
#   in caddyLib.mkProjectPort { name = "myproject"; }
# ==============================================================================
{
  pkgs,
  lib,
}:
rec {
  portsLib = import ../ports.nix { inherit lib; };

  mkProjectPort =
    {
      name,
      minPort ? portsLib.defaults.minPort,
      portRange ? portsLib.defaults.portRange,
      modulus ? portsLib.defaults.modulus,
    }:
    portsLib.computeBasePort {
      inherit name minPort portRange modulus;
    };


  # Create Caddy management scripts
  # Returns an attrset of derivations that can be added to packages
  mkCaddyScripts =
    {
      # Optional: Step CA configuration for TLS
      stepEnabled ? false,
      stepCaUrl ? "",
      stepCaFingerprint ? "",
    }:
    let
      # All paths are computed at runtime using $HOME
      # This avoids purity issues with builtins.getEnv
      # Script to ensure config directories exist
      ensureConfigDir = pkgs.writeShellScriptBin "caddy-ensure-config" ''
        # syntax: bash
        set -euo pipefail
        CADDY_CONFIG_DIR="''${CADDY_CONFIG_DIR:-$HOME/.config/caddy}"
        CADDY_SITES_DIR="$CADDY_CONFIG_DIR/sites.d"

        mkdir -p "$CADDY_CONFIG_DIR"
        mkdir -p "$CADDY_SITES_DIR"
        echo "Caddy config directories created at $CADDY_CONFIG_DIR"
      '';

      # Script to fetch root CA cert if step is enabled
      ensureRootCert = pkgs.writeShellScriptBin "caddy-ensure-root-cert" ''
        set -euo pipefail
        CADDY_CONFIG_DIR="''${CADDY_CONFIG_DIR:-$HOME/.config/caddy}"
        ROOT_CERT_PATH="$CADDY_CONFIG_DIR/root_ca.crt"

        ${
          if stepEnabled then
            ''
              if [[ ! -f "$ROOT_CERT_PATH" ]]; then
                echo "Fetching root CA certificate from Step CA..."
                if ${pkgs.step-cli}/bin/step ca roots \
                  "$ROOT_CERT_PATH" \
                  --ca-url "${stepCaUrl}" \
                  --fingerprint "${stepCaFingerprint}" 2>/dev/null; then
                  echo "Root CA certificate saved to $ROOT_CERT_PATH"
                else
                  echo "Warning: Could not fetch root CA certificate (Step CA may be unreachable)"
                  echo "Caddy will work without Step CA TLS"
                fi
              else
                echo "Root CA certificate already exists at $ROOT_CERT_PATH"
              fi

              # Verify the cert is valid (if it exists)
              if [[ -f "$ROOT_CERT_PATH" ]]; then
                if ! ${pkgs.step-cli}/bin/step certificate verify "$ROOT_CERT_PATH" --roots="$ROOT_CERT_PATH" 2>/dev/null; then
                  echo "Warning: Root CA certificate may be invalid, refetching..."
                  ${pkgs.step-cli}/bin/step ca roots \
                    "$ROOT_CERT_PATH" \
                    --ca-url "${stepCaUrl}" \
                    --fingerprint "${stepCaFingerprint}" \
                    --force 2>/dev/null || true
                fi
              fi
            ''
          else
            ''
              echo "Step CA is not enabled, skipping root cert fetch"
            ''
        }
      '';

      # Script to generate the main Caddyfile that imports all sites
      generateCaddyfile = pkgs.writeShellScriptBin "caddy-generate-config" ''
              # syntax: bash
              set -euo pipefail
              CADDY_CONFIG_DIR="''${CADDY_CONFIG_DIR:-$HOME/.config/caddy}"
              CADDY_SITES_DIR="$CADDY_CONFIG_DIR/sites.d"
              CADDYFILE_PATH="$CADDY_CONFIG_DIR/Caddyfile"

              ${ensureConfigDir}/bin/caddy-ensure-config
              ${ensureRootCert}/bin/caddy-ensure-root-cert

              cat > "$CADDYFILE_PATH" <<EOF
        # Generated Caddyfile - imports all sites from sites.d/
        # Do not edit directly, use caddy-add-site instead

        {
          # Global options
          admin off
        }

        # Import all site configurations
        import $CADDY_SITES_DIR/*.caddy
        EOF

              echo "Generated Caddyfile at $CADDYFILE_PATH"
      '';

      # Script to start/restart caddy
      caddyStart = pkgs.writeShellScriptBin "caddy-start" ''
        set -euo pipefail
        CADDY_CONFIG_DIR="''${CADDY_CONFIG_DIR:-$HOME/.config/caddy}"
        CADDYFILE_PATH="$CADDY_CONFIG_DIR/Caddyfile"
        PID_FILE="$CADDY_CONFIG_DIR/caddy.pid"

        ${generateCaddyfile}/bin/caddy-generate-config

        # Check if caddy is already running
        if [[ -f "$PID_FILE" ]]; then
          pid=$(cat "$PID_FILE")
          if kill -0 "$pid" 2>/dev/null; then
            echo "Caddy is already running (PID: $pid), reloading..."
            ${pkgs.caddy}/bin/caddy reload --config "$CADDYFILE_PATH" --force
            exit 0
          else
            echo "Stale PID file found, removing..."
            rm -f "$PID_FILE"
          fi
        fi

        echo "Starting Caddy..."
        ${pkgs.caddy}/bin/caddy start --config "$CADDYFILE_PATH" --pidfile "$PID_FILE"
        echo "Caddy started (PID file: $PID_FILE)"
      '';

      # Script to stop caddy
      caddyStop = pkgs.writeShellScriptBin "caddy-stop" ''
        set -euo pipefail
        CADDY_CONFIG_DIR="''${CADDY_CONFIG_DIR:-$HOME/.config/caddy}"
        PID_FILE="$CADDY_CONFIG_DIR/caddy.pid"

        if [[ -f "$PID_FILE" ]]; then
          pid=$(cat "$PID_FILE")
          if kill -0 "$pid" 2>/dev/null; then
            echo "Stopping Caddy (PID: $pid)..."
            ${pkgs.caddy}/bin/caddy stop
            rm -f "$PID_FILE"
            echo "Caddy stopped"
          else
            echo "Caddy not running (stale PID file)"
            rm -f "$PID_FILE"
          fi
        else
          echo "Caddy not running (no PID file)"
        fi
      '';

      # Script to restart caddy
      caddyRestart = pkgs.writeShellScriptBin "caddy-restart" ''
        set -euo pipefail
        ${caddyStop}/bin/caddy-stop || true
        ${caddyStart}/bin/caddy-start
      '';

      # Script to check caddy status
      caddyStatus = pkgs.writeShellScriptBin "caddy-status" ''
        set -euo pipefail
        CADDY_CONFIG_DIR="''${CADDY_CONFIG_DIR:-$HOME/.config/caddy}"
        PID_FILE="$CADDY_CONFIG_DIR/caddy.pid"

        if [[ -f "$PID_FILE" ]]; then
          pid=$(cat "$PID_FILE")
          if kill -0 "$pid" 2>/dev/null; then
            echo "Caddy is running (PID: $pid)"
            exit 0
          else
            echo "Caddy is not running (stale PID file)"
            exit 1
          fi
        else
          echo "Caddy is not running"
          exit 1
        fi
      '';

      # Script to add/update a virtual host
      caddyAddSite = pkgs.writeShellScriptBin "caddy-add-site" ''
              set -euo pipefail
              CADDY_CONFIG_DIR="''${CADDY_CONFIG_DIR:-$HOME/.config/caddy}"
              CADDY_SITES_DIR="$CADDY_CONFIG_DIR/sites.d"

              ${ensureConfigDir}/bin/caddy-ensure-config

              if [[ $# -lt 2 ]]; then
                echo "Usage: caddy-add-site <domain> <upstream> [options]"
                echo ""
                echo "Arguments:"
                echo "  domain    - The domain name (e.g., app.localhost, myapp.internal)"
                echo "  upstream  - The upstream address (e.g., localhost:3000, 127.0.0.1:8080)"
                echo ""
                echo "Options:"
                echo "  --project <name>  Project name prefix for site file (avoids collisions)"
                echo "  --tls-internal    Use internal TLS (Step CA)"
                echo "  --tls-off         Disable TLS"
                echo ""
                echo "Examples:"
                echo "  caddy-add-site app.localhost localhost:3000 --project myapp"
                echo "  caddy-add-site api.internal localhost:8080 --tls-internal --project myapp"
                exit 1
              fi

              domain="$1"
              upstream="$2"
              shift 2

              tls_config=""
              project_prefix=""
              while [[ $# -gt 0 ]]; do
                case "$1" in
                  --project)
                    project_prefix="$2_"
                    shift 2
                    ;;
                  --tls-internal)
                    tls_config="tls internal"
                    shift
                    ;;
                  --tls-off)
                    tls_config=""
                    shift
                    ;;
                  *)
                    echo "Unknown option: $1"
                    exit 1
                    ;;
                esac
              done

              # Sanitize domain for filename, with optional project prefix
              domain_part=$(echo "$domain" | tr '.' '_' | tr ':' '_')
              filename="''${project_prefix}''${domain_part}"
              sitefile="$CADDY_SITES_DIR/$filename.caddy"

              cat > "$sitefile" <<EOF
        # Site: $domain -> $upstream
        $domain {
          $tls_config
          reverse_proxy $upstream
        }
        EOF

              echo "Site configuration saved to $sitefile"
              echo ""
              echo "Run 'caddy-start' or 'caddy-restart' to apply changes"
      '';

      # Script to remove a virtual host
      caddyRemoveSite = pkgs.writeShellScriptBin "caddy-remove-site" ''
        set -euo pipefail
        CADDY_CONFIG_DIR="''${CADDY_CONFIG_DIR:-$HOME/.config/caddy}"
        CADDY_SITES_DIR="$CADDY_CONFIG_DIR/sites.d"

        if [[ $# -lt 1 ]]; then
          echo "Usage: caddy-remove-site <domain> [--project <name>]"
          exit 1
        fi

        domain="$1"
        shift

        project_prefix=""
        while [[ $# -gt 0 ]]; do
          case "$1" in
            --project)
              project_prefix="$2_"
              shift 2
              ;;
            *)
              echo "Unknown option: $1"
              exit 1
              ;;
          esac
        done

        domain_part=$(echo "$domain" | tr '.' '_' | tr ':' '_')
        filename="''${project_prefix}''${domain_part}"
        sitefile="$CADDY_SITES_DIR/$filename.caddy"

        if [[ -f "$sitefile" ]]; then
          rm "$sitefile"
          echo "Removed site configuration for $domain"
          echo "Run 'caddy-restart' to apply changes"
        else
          echo "No site configuration found for $domain (looked for $sitefile)"
          exit 1
        fi
      '';

      # Script to list all configured sites
      caddyListSites = pkgs.writeShellScriptBin "caddy-list-sites" ''
        set -euo pipefail
        CADDY_CONFIG_DIR="''${CADDY_CONFIG_DIR:-$HOME/.config/caddy}"
        CADDY_SITES_DIR="$CADDY_CONFIG_DIR/sites.d"

        if [[ -d "$CADDY_SITES_DIR" ]]; then
          sites=$(ls -1 "$CADDY_SITES_DIR"/*.caddy 2>/dev/null || true)
          if [[ -n "$sites" ]]; then
            echo "Configured sites:"
            for site in "$CADDY_SITES_DIR"/*.caddy; do
              if [[ -f "$site" ]]; then
                # Extract domain from first non-comment line
                domain=$(grep -v '^#' "$site" | grep -v '^\s*$' | head -1 | awk '{print $1}')
                echo "  - $domain ($(basename "$site"))"
              fi
            done
          else
            echo "No sites configured"
          fi
        else
          echo "Sites directory does not exist yet"
        fi
      '';

      # Script to get project port based on current directory
      caddyProjectPort = pkgs.writeShellScriptBin "caddy-project-port" ''
        set -euo pipefail

        dir="''${1:-$(pwd)}"

        # Generate a hash of the directory path (matching Nix implementation)
        # Uses MD5, takes first 4 hex chars, maps to port range 3000-9999
        hash=$(echo -n "$dir" | md5sum | cut -c1-4)

        # Convert hex to decimal and map to port range 3000-9999
        decimal=$((16#$hash))
        min_port=3000
        port_range=7000
        port=$((min_port + (decimal % port_range)))

        echo "$port"
      '';
    in
    {
      inherit
        ensureConfigDir
        ensureRootCert
        generateCaddyfile
        caddyStart
        caddyStop
        caddyRestart
        caddyStatus
        caddyAddSite
        caddyRemoveSite
        caddyListSites
        caddyProjectPort
        ;

      # Required packages
      requiredPackages = [ pkgs.caddy ] ++ lib.optionals stepEnabled [ pkgs.step-cli ];

      # All packages together
      # NOTE: Legacy scripts (caddyStart, caddyStop, caddyRestart, caddyStatus, etc.)
      # are still defined above for internal use but NOT exposed in allPackages.
      # The Go CLI (`stackpanel caddy *`) now handles all Caddy management.
      # Only essential utilities are exported.
      allPackages = [
        ensureConfigDir
        ensureRootCert
        caddyProjectPort
        pkgs.caddy
      ]
      ++ lib.optionals stepEnabled [ pkgs.step-cli ];
    };
}
