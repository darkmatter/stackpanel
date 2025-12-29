# ==============================================================================
# aws.nix
#
# AWS Roles Anywhere certificate authentication module for devenv.
#
# This module provides passwordless AWS access using device certificates
# issued by Step CA. It integrates with AWS Roles Anywhere to exchange
# X.509 certificates for temporary AWS credentials.
#
# Features:
#   - Automatic credential fetching and caching
#   - Interactive setup prompts
#   - Integration with chamber for secrets injection
#
# Prerequisites:
#   - Step CA device certificate (via stackpanel.network.step)
#   - AWS Roles Anywhere trust anchor and profile configured
#
# Usage:
#   stackpanel.aws.certAuth = {
#     enable = true;
#     account-id = "123456789";
#     role-name = "developer";
#     trust-anchor-arn = "arn:aws:...";
#     profile-arn = "arn:aws:...";
#   };
# ==============================================================================
{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.stackpanel.aws.certAuth;
  # Use fallback for standalone evaluation (docs generation, nix eval, etc.)
  dirs = config.stackpanel.dirs or { state = ".stackpanel/state"; };
  baseStateDir = dirs.state;


  stateDir = "${baseStateDir}/aws";
  stepStateDir = "${baseStateDir}/step";
  skipFile = "${stateDir}/.skip-setup-prompt";

  # Check if Step CA cert exists (AWS cert-auth depends on it)
  stepCertPath = "${stepStateDir}/device-root.chain.crt";
  stepKeyPath = "${stepStateDir}/device.key";

  # Import shared AWS library
  awsLib = import ../lib/services/aws.nix {inherit pkgs lib;};
in {
  config = lib.mkIf cfg.enable (
    let
      # Create scripts using shared library - only evaluated when enabled
      awsScripts = awsLib.mkAwsCredScripts {
        stateDir = baseStateDir;
        accountId = cfg.account-id;
        roleName = cfg.role-name;
        trustAnchorArn = cfg.trust-anchor-arn;
        profileArn = cfg.profile-arn;
        region = cfg.region;
        cacheBufferSeconds = cfg.cache-buffer-seconds;
      };

      # Check if AWS cert-auth is working
      checkAwsCert = pkgs.writeShellScriptBin "check-aws-cert" ''
        set -uo pipefail

        red='\033[0;31m'
        green='\033[0;32m'
        nc='\033[0m'

        pass() { echo -e "''${green}OK''${nc}"; }
        fail() { echo -e "''${red}FAIL''${nc}"; }

        all_passed=true

        echo -n "Checking if device certificate exists... "
        if [[ -f "${stepCertPath}" && -f "${stepKeyPath}" ]]; then
          pass
        else
          fail
          echo "  Hint: Run 'ensure-device-cert' first (Step CA required)"
          all_passed=false
        fi

        if [[ -f "${stepCertPath}" ]]; then
          echo -n "Checking if AWS credentials can be fetched... "
          if eval "$(${awsScripts.awsCredsEnv}/bin/aws-creds-env 2>/dev/null)" && \
             [[ -n "''${AWS_ACCESS_KEY_ID:-}" ]]; then
            pass
          else
            fail
            echo "  Hint: Check Roles Anywhere configuration"
            all_passed=false
          fi
        fi

        echo ""
        if $all_passed; then
          echo -e "''${green}AWS cert-auth is configured!''${nc}"
          exit 0
        else
          echo -e "''${red}AWS cert-auth not ready.''${nc}"
          exit 1
        fi
      '';

      # Interactive setup prompt script
      interactiveSetup = pkgs.writeShellScriptBin "aws-cert-setup-prompt" ''
        set -uo pipefail

        # Check if user chose "don't ask again"
        if [[ -f "${skipFile}" ]]; then
          exit 0
        fi

        # Check if AWS cert-auth is already working
        if ${checkAwsCert}/bin/check-aws-cert >/dev/null 2>&1; then
          exit 0
        fi

        # Check if Step CA cert exists first
        if [[ ! -f "${stepCertPath}" || ! -f "${stepKeyPath}" ]]; then
          # Step CA not set up yet - don't prompt, let the Step CA module handle it
          exit 0
        fi

        # Show description and prompt
        echo ""
        ${pkgs.gum}/bin/gum style \
          --foreground 208 --border-foreground 208 --border double \
          --align center --width 60 --margin "1 2" --padding "1 2" \
          "AWS Roles Anywhere Setup"

        echo ""
        ${pkgs.gum}/bin/gum style --foreground 250 "
    AWS Roles Anywhere lets you access AWS without long-lived keys.
    Using your device certificate, you can:

      • Access AWS services (S3, EC2, etc.) securely
      • Fetch secrets from Parameter Store / Secrets Manager
      • Use 'chamber' for environment variable injection

    Your credentials are fetched on-demand and cached temporarily.
    Account: ${cfg.account-id}
    Role:    ${cfg.role-name}
    "

        choice=$(${pkgs.gum}/bin/gum choose \
          "Test connection now" \
          "Skip for now" \
          "Don't ask again")

        case "$choice" in
          "Test connection now")
            echo ""
            ${checkAwsCert}/bin/check-aws-cert
            ;;
          "Don't ask again")
            mkdir -p "${stateDir}"
            touch "${skipFile}"
            ${pkgs.gum}/bin/gum style --foreground 245 \
              "Got it! You can run 'check-aws-cert' manually when ready."
            ${pkgs.gum}/bin/gum style --foreground 245 \
              "To re-enable prompts, delete: ${skipFile}"
            ;;
          *)
            ${pkgs.gum}/bin/gum style --foreground 245 \
              "Skipped. Run 'check-aws-cert' to verify setup."
            ;;
        esac
      '';
    in {
      stackpanel.devshell.packages = awsScripts.allPackages ++ [pkgs.gum checkAwsCert interactiveSetup];

      stackpanel.motd.commands = [
        {
          name = "aws-creds-env";
          description = "Export AWS credentials to env";
        }
        {
          name = "check-aws-cert";
          description = "Verify AWS cert-auth status";
        }
      ];
      stackpanel.motd.features = ["AWS Roles Anywhere (${cfg.role-name})"];

      # Set base AWS env vars (AWS_CONFIG_FILE is set in hooks with absolute path)
      stackpanel.devshell.env = awsScripts.env;

      stackpanel.devshell.hooks.main = [
        ''
          # Set AWS_CONFIG_FILE using STACKPANEL_STATE_DIR (absolute, works in Docker too)
          export AWS_CONFIG_FILE="$STACKPANEL_STATE_DIR/aws/config"

          # Generate AWS config with credential_process for auto-refresh
          _step_cert="$STACKPANEL_STATE_DIR/step/device-root.chain.crt"
          _step_key="$STACKPANEL_STATE_DIR/step/device.key"
          if [[ -f "$_step_cert" && -f "$_step_key" ]]; then
            mkdir -p "$STACKPANEL_STATE_DIR/aws"
            AWS_CERT_PATH="$_step_cert" AWS_KEY_PATH="$_step_key" \
              ${awsScripts.generateAwsConfig}/bin/aws-generate-config "$AWS_CONFIG_FILE" 2>/dev/null || true
          fi

          ${lib.optionalString cfg.prompt-on-shell ''
            # Interactive AWS cert-auth setup (errors should not crash the shell)
            ${interactiveSetup}/bin/aws-cert-setup-prompt || true
          ''}
        ''
      ];
    }
  );
}
