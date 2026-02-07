# ==============================================================================
# builder.nix - Linux Builder Detection and Configuration
#
# Ensures team members can build Linux containers on macOS by:
#   1. Detecting if Determinate Nix native Linux builder is available
#   2. Falling back to a remote builder if configured
#   3. Providing helpful instructions if neither is available
#
# Configuration:
#   stackpanel.containers.builder = {
#     enable = true;  # Enable builder detection (default: true)
#     remote = {
#       enable = true;  # Enable remote builder fallback
#       host = "100.102.113.26";
#       user = "root";
#       sshKeyPath = "/etc/nix/builder_ed25519";
#       systems = [ "x86_64-linux" "aarch64-linux" ];
#       maxJobs = 16;
#       speedFactor = 1;
#       supportedFeatures = [ "big-parallel" "benchmark" "kvm" "nixos-test" ];
#     };
#     warnIfMissing = true;  # Show warning if no builder available
#   };
#
# ==============================================================================
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.stackpanel.containers.builder;
  spCfg = config.stackpanel;

  # Build the remote builder machines entry
  # Format: ssh://user@host system sshKeyPath maxJobs speedFactor features
  remoteBuilderEntry =
    let
      r = cfg.remote;
      features = lib.concatStringsSep "," r.supportedFeatures;
      systems = lib.concatStringsSep "," r.systems;
    in
    "ssh://${r.user}@${r.host} ${systems} ${r.sshKeyPath} ${toString r.maxJobs} ${toString r.speedFactor} ${features}";

  # Script to check if native Linux builder is available
  checkBuilderScript = pkgs.writeShellScript "check-linux-builder" ''
    set -euo pipefail

    # Check if we're on macOS
    if [[ "$(uname)" != "Darwin" ]]; then
      echo "native"  # On Linux, we can build natively
      exit 0
    fi

    # Check if Determinate Nix native builder feature is enabled
    if command -v determinate-nixd &>/dev/null; then
      if determinate-nixd version 2>/dev/null | grep -q "native-linux-builder"; then
        echo "determinate"
        exit 0
      fi
    fi

    # Check if a remote builder is configured in nix.conf
    if nix config show builders 2>/dev/null | grep -q "linux"; then
      echo "remote"
      exit 0
    fi

    # Check if external-builders is configured (Determinate Nix)
    if nix config show external-builders 2>/dev/null | grep -qv '^\[\]$'; then
      echo "external"
      exit 0
    fi

    echo "none"
  '';

  # Script to configure remote builder (writes to nix.custom.conf)
  configureRemoteBuilderScript = pkgs.writeShellScript "configure-remote-builder" ''
    set -euo pipefail

    BUILDER_ENTRY="${remoteBuilderEntry}"
    NIX_CUSTOM_CONF="/etc/nix/nix.custom.conf"

    echo "🔧 Configuring remote Linux builder..."
    echo "   Host: ${cfg.remote.host}"
    echo "   Systems: ${lib.concatStringsSep ", " cfg.remote.systems}"

    # Check if SSH key exists
    if [[ ! -f "${cfg.remote.sshKeyPath}" ]]; then
      echo "❌ SSH key not found: ${cfg.remote.sshKeyPath}"
      echo ""
      echo "To set up the remote builder:"
      echo "  1. Generate an SSH key: ssh-keygen -t ed25519 -f ${cfg.remote.sshKeyPath} -N \"\""
      echo "  2. Copy the public key to the builder: ssh-copy-id -i ${cfg.remote.sshKeyPath}.pub ${cfg.remote.user}@${cfg.remote.host}"
      echo "  3. Re-enter the devshell"
      exit 1
    fi

    # Check if builder is already configured
    if grep -q "builders.*${cfg.remote.host}" "$NIX_CUSTOM_CONF" 2>/dev/null; then
      echo "✅ Remote builder already configured in $NIX_CUSTOM_CONF"
      exit 0
    fi

    # Add builder configuration
    echo ""
    echo "Adding to $NIX_CUSTOM_CONF (requires sudo):"
    echo "  builders = $BUILDER_ENTRY"
    echo "  builders-use-substitutes = true"
    echo ""

    # Use sudo to append to nix.custom.conf
    if sudo bash -c "echo 'builders = $BUILDER_ENTRY' >> '$NIX_CUSTOM_CONF' && echo 'builders-use-substitutes = true' >> '$NIX_CUSTOM_CONF'"; then
      echo "✅ Remote builder configured!"
      echo ""
      echo "Restarting Nix daemon..."
      if [[ "$(uname)" == "Darwin" ]]; then
        sudo launchctl kickstart -k system/systems.determinate.nix-daemon 2>/dev/null || \
        sudo launchctl kickstart -k system/org.nixos.nix-daemon 2>/dev/null || \
        echo "⚠️  Could not restart daemon automatically. Please restart it manually."
      else
        sudo systemctl restart nix-daemon 2>/dev/null || \
        echo "⚠️  Could not restart daemon automatically. Please restart it manually."
      fi
    else
      echo "❌ Failed to configure remote builder"
      exit 1
    fi
  '';

  # Shell hook for builder detection
  builderHook = ''
    # Linux builder detection for container builds
    __stackpanel_check_linux_builder() {
      # Skip on Linux
      if [[ "$(uname)" != "Darwin" ]]; then
        return 0
      fi

      local builder_status
      builder_status="$(${checkBuilderScript})"

      case "$builder_status" in
        native|determinate|external)
          # Native or Determinate Nix builder available
          export STACKPANEL_LINUX_BUILDER="$builder_status"
          ;;
        remote)
          # Remote builder configured
          export STACKPANEL_LINUX_BUILDER="remote"
          ;;
        none)
          export STACKPANEL_LINUX_BUILDER="none"
          ${lib.optionalString cfg.warnIfMissing ''
            echo "" >&2
            echo "⚠️  No Linux builder configured for container builds" >&2
            echo "" >&2
            echo "Options to enable Linux builds on macOS:" >&2
            echo "" >&2
            echo "  1. Determinate Nix Native Builder (recommended):" >&2
            echo "     - Log in to FlakeHub: determinate-nixd auth login" >&2
            echo "     - Request access at: support@determinate.systems" >&2
            echo "     - Restart daemon: sudo launchctl kickstart -k system/systems.determinate.nix-daemon" >&2
            echo "" >&2
            ${lib.optionalString cfg.remote.enable ''
              echo "  2. Remote Builder (auto-configure):" >&2
              echo "     Run: configure-linux-builder" >&2
              echo "" >&2
            ''}
            echo "  3. Manual remote builder setup:" >&2
            echo "     See: https://nixcademy.com/posts/macos-linux-builder/" >&2
            echo "" >&2
          ''}
          ;;
      esac
    }
    __stackpanel_check_linux_builder
  '';

in
{
  options.stackpanel.containers.builder = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Linux builder detection and configuration helpers.";
    };

    warnIfMissing = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Show a warning if no Linux builder is available on macOS.";
    };

    remote = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Enable remote builder fallback configuration.
          When enabled, provides a script to automatically configure
          a remote Linux builder for team members.
        '';
      };

      host = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = "100.102.113.26";
        description = "Hostname or IP address of the remote Linux builder.";
      };

      user = lib.mkOption {
        type = lib.types.str;
        default = "root";
        description = "SSH user for the remote builder.";
      };

      sshKeyPath = lib.mkOption {
        type = lib.types.str;
        default = "/etc/nix/builder_ed25519";
        description = "Path to the SSH private key for the remote builder.";
      };

      systems = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "x86_64-linux" ];
        example = [
          "x86_64-linux"
          "aarch64-linux"
        ];
        description = "Linux systems supported by the remote builder.";
      };

      maxJobs = lib.mkOption {
        type = lib.types.int;
        default = 16;
        description = "Maximum number of parallel jobs on the remote builder.";
      };

      speedFactor = lib.mkOption {
        type = lib.types.int;
        default = 1;
        description = "Speed factor for the remote builder (higher = preferred).";
      };

      supportedFeatures = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "big-parallel"
          "benchmark"
          "kvm"
          "nixos-test"
        ];
        description = "Nix features supported by the remote builder.";
      };
    };
  };

  config = lib.mkIf (spCfg.enable && cfg.enable) {
    # Add builder detection hook
    stackpanel.devshell.hooks.before = lib.mkAfter [ builderHook ];

    # Add configuration script if remote builder is enabled
    stackpanel.scripts = lib.mkIf cfg.remote.enable {
      configure-linux-builder = {
        description = "Configure remote Linux builder for container builds";
        exec = ''
          ${configureRemoteBuilderScript}
        '';
      };

      check-linux-builder = {
        description = "Check which Linux builder is available";
        exec = ''
          builder_type="$(${checkBuilderScript})"
          case "$builder_type" in
            native)
              echo "✅ Native Linux (running on Linux)"
              ;;
            determinate)
              echo "✅ Determinate Nix native Linux builder"
              ;;
            external)
              echo "✅ External builder configured"
              ;;
            remote)
              echo "✅ Remote builder configured"
              nix config show builders 2>/dev/null | grep linux || true
              ;;
            none)
              echo "❌ No Linux builder available"
              exit 1
              ;;
          esac
        '';
      };
    };

    # Export builder info for other modules
    stackpanel.devshell.env = {
      STACKPANEL_REMOTE_BUILDER_HOST = lib.mkIf cfg.remote.enable cfg.remote.host;
    };
  };
}
