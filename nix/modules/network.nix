# Step CA certificate management for devenv
#
# Usage in devenv.nix:
#   stackpanel.network.step = {
#     enable = true;
#     caUrl = "https://ca.internal:443";
#     caFingerprint = "...";
#   };
#
{
  pkgs,
  lib,
  config,
  options,
  ...
}: let
  cfg = config.stackpanel.network.step;
  # Use fallback for standalone evaluation (docs generation, nix eval, etc.)
  dirs = config.stackpanel.dirs or { state = ".stackpanel/state"; };
  stateDir = "${dirs.state}/step";
  skipFile = "${stateDir}/.skip-setup-prompt";

  # Detect if we're in devenv context (enterShell option is declared) vs standalone eval
  isDevenv = options ? enterShell;

  # Import shared network library
  networkLib = import ../lib/network.nix {inherit pkgs lib;};
in {
  options.stackpanel.network.step = {
    enable = lib.mkEnableOption "Step CA certificate management";

    ca-url = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Step CA URL (e.g., https://ca.internal:443)";
    };

    ca-fingerprint = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Step CA root certificate fingerprint";
    };

    provisioner = lib.mkOption {
      type = lib.types.str;
      default = "Authentik";
      description = "Step CA provisioner name";
    };

    cert-name = lib.mkOption {
      type = lib.types.str;
      default = "device";
      description = "Common name for the device certificate";
    };

    prompt-on-shell = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Prompt for certificate setup on shell entry if not configured";
    };

    enterShell = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Scripts to run when entering the shell (internal)";
    };
  };

  config = lib.mkIf cfg.enable (
    let
      # Create scripts using shared library - only evaluated when enabled
      stepScripts = networkLib.mkStepScripts {
        inherit stateDir;
        caUrl = cfg.ca-url;
        caFingerprint = cfg.ca-fingerprint;
        provisioner = cfg.provisioner;
        certName = cfg.cert-name;
      };

      # Interactive setup prompt script
      interactiveSetup = pkgs.writeShellScriptBin "step-cert-setup-prompt" ''
        set -uo pipefail

        # Check if user chose "don't ask again"
        if [[ -f "${skipFile}" ]]; then
          exit 0
        fi

        # Check if cert already exists and is valid
        if ${stepScripts.checkCert}/bin/check-device-cert >/dev/null 2>&1; then
          exit 0
        fi

        # Show description and prompt
        echo ""
        ${pkgs.gum}/bin/gum style \
          --foreground 212 --border-foreground 212 --border double \
          --align center --width 60 --margin "1 2" --padding "1 2" \
          "Step CA Certificate Setup"

        echo ""
        ${pkgs.gum}/bin/gum style --foreground 250 "
    Step CA provides secure TLS certificates for internal services.
    With a device certificate, you can:

      • Access internal APIs and services securely
      • Authenticate to AWS using Roles Anywhere
      • Connect to databases without passwords

    Your certificate will be stored locally and renewed automatically.
    "

        choice=$(${pkgs.gum}/bin/gum choose \
          "Set up now" \
          "Skip for now" \
          "Don't ask again")

        case "$choice" in
          "Set up now")
            echo ""
            ${stepScripts.ensureCert}/bin/ensure-device-cert
            ;;
          "Don't ask again")
            mkdir -p "${stateDir}"
            touch "${skipFile}"
            ${pkgs.gum}/bin/gum style --foreground 245 \
              "Got it! You can run 'ensure-device-cert' manually when ready."
            ${pkgs.gum}/bin/gum style --foreground 245 \
              "To re-enable prompts, delete: ${skipFile}"
            ;;
          *)
            ${pkgs.gum}/bin/gum style --foreground 245 \
              "Skipped. Run 'ensure-device-cert' when ready."
            ;;
        esac
      '';
    in lib.optionalAttrs isDevenv {
      packages = stepScripts.allPackages ++ [pkgs.gum interactiveSetup];

      stackpanel.motd.commands = [
        {
          name = "ensure-device-cert";
          description = "Request/renew device certificate";
        }
        {
          name = "check-device-cert";
          description = "Verify certificate status";
        }
      ];
      stackpanel.motd.features = ["Step CA certificates (${cfg.ca-url})"];

      stackpanel.network.step.enterShell = lib.mkIf cfg.prompt-on-shell ''
        # Interactive Step CA cert setup
        ${interactiveSetup}/bin/step-cert-setup-prompt
      '';
    }
  );
}
