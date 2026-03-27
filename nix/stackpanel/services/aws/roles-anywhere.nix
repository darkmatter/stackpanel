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
#   stackpanel.aws.roles-anywhere = {
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
}:
let
  cfg = config.stackpanel.aws.roles-anywhere;
  # Use fallback for standalone evaluation (docs generation, nix eval, etc.)
  dirs = config.stackpanel.dirs or { state = ".stack/profile"; profile = ".stack/profile"; };
  baseStateDir = dirs.state;

  # Import util for debug logging
  util = config.stackpanel.util;

  stateDir = "${baseStateDir}/aws";
  stepStateDir = "${baseStateDir}/step";
  skipFile = "${stateDir}/.skip-setup-prompt";

  # Check if Step CA cert exists (AWS cert-auth depends on it)
  stepCertPath = "${stepStateDir}/device-root.chain.crt";
  stepKeyPath = "${stepStateDir}/device.key";

  # Import shared AWS library (colocated)
  awsLib = import ./lib.nix { inherit pkgs lib; };
in
{
  config = lib.mkIf cfg.enable (
    let
      # Root-level AWS config
      awsCfg = config.stackpanel.aws;

      # Create scripts using runtime paths (Step CA certs are generated at runtime)
      awsScripts = awsLib.mkRuntimeAwsScripts {
        # These are resolved at runtime via environment variables
        certPath = "$STACKPANEL_STATE_DIR/step/device-root.chain.crt";
        keyPath = "$STACKPANEL_STATE_DIR/step/device.key";
        accountId = cfg.account-id;
        roleName = cfg.role-name;
        trustAnchorArn = cfg.trust-anchor-arn;
        profileArn = cfg.profile-arn;
        region = cfg.region;
        debug = config.stackpanel.debug;
        # Profile and extra config options from root-level stackpanel.aws
        defaultProfile = if awsCfg.default-profile or "" == "" then "default" else awsCfg.default-profile;
        extraConfig = awsCfg.extra-config or "";
      };

      # Check if AWS cert-auth is working
      checkAwsCert = pkgs.writeShellScriptBin "check-aws-cert" ''
        set -uo pipefail
        ${util.log.debug "check-aws-cert: starting certificate verification"}

        red='\033[0;31m'
        green='\033[0;32m'
        nc='\033[0m'

        pass() { echo -e "''${green}OK''${nc}"; }
        fail() { echo -e "''${red}FAIL''${nc}"; }

        all_passed=true
        _needs_regen=false

        _cert="$STACKPANEL_STATE_DIR/step/device-root.chain.crt"
        _key="$STACKPANEL_STATE_DIR/step/device.key"

        echo -n "Checking if device certificate exists... "
        if [[ -f "$_cert" && -f "$_key" ]]; then
          ${util.log.debug "check-aws-cert: found cert at $_cert"}
          pass
        else
          ${util.log.debug "check-aws-cert: cert not found at $_cert"}
          fail
          echo "  Hint: Run 'ensure-device-cert' first (Step CA required)"
          all_passed=false
        fi

        if [[ -f "$_cert" ]]; then
          echo -n "Checking if AWS credentials can be fetched... "
          ${util.log.debug "check-aws-cert: attempting credential fetch via sts get-caller-identity"}

          # Set up AWS config for credential_process auth
          eval "$(${awsScripts.awsCredsEnv}/bin/aws-creds-env 2>/dev/null)"

          # Test credentials by calling AWS STS
          if ${pkgs.awscli2}/bin/aws sts get-caller-identity >/dev/null 2>&1; then
            ${util.log.debug "check-aws-cert: credentials fetched successfully"}
            pass
          else
            ${util.log.debug "check-aws-cert: credential fetch failed"}
            fail
            all_passed=false

            # Check if the cert might be expired or invalid
            cert_expiry=$(${pkgs.openssl}/bin/openssl x509 -enddate -noout -in "$_cert" 2>/dev/null | cut -d= -f2)
            if [[ -n "$cert_expiry" ]]; then
              cert_epoch=$(date -d "$cert_expiry" +%s 2>/dev/null || date -jf "%b %d %T %Y %Z" "$cert_expiry" +%s 2>/dev/null || echo "0")
              now_epoch=$(date +%s)
              if [[ "$cert_epoch" -lt "$now_epoch" ]]; then
                echo "  Certificate expired on: $cert_expiry"
                echo "  Hint: Run 'ensure-device-cert' to regenerate"
                _needs_regen=true
              else
                echo "  Certificate valid until: $cert_expiry"
                echo "  Hint: Check Roles Anywhere configuration (trust anchor, profile, role)"
              fi
            else
              echo "  Hint: Check Roles Anywhere configuration"
            fi
          fi
        fi

        echo ""
        if $all_passed; then
          ${util.log.debug "check-aws-cert: all checks passed"}
          echo -e "''${green}AWS cert-auth is configured!''${nc}"
          exit 0
        else
          ${util.log.debug "check-aws-cert: some checks failed"}
          echo -e "''${red}AWS cert-auth not ready.''${nc}"

          # Offer to regenerate cert if it might help
          if [[ "''${_needs_regen:-false}" == "true" ]]; then
            echo ""
            if ${pkgs.gum}/bin/gum confirm "Would you like to regenerate the device certificate?"; then
              echo ""
              echo "Removing expired certificate..."
              rm -f "$_cert" "$_key" "$STACKPANEL_STATE_DIR/step/device.crt"
              echo ""
              ensure-device-cert
              echo ""
              echo "Retrying AWS auth check..."
              exec "$0"  # Re-run this script
            fi
          fi

          exit 1
        fi
      '';

      # Interactive setup prompt script
      interactiveSetup = pkgs.writeShellScriptBin "aws-cert-setup-prompt" ''
            set -uo pipefail
            ${util.log.debug "aws-cert-setup-prompt: starting"}

            _skip_file="$STACKPANEL_STATE_DIR/aws/.skip-setup-prompt"

            # Check if user chose "don't ask again"
            if [[ -f "$_skip_file" ]]; then
              ${util.log.debug "aws-cert-setup-prompt: skip file exists, exiting"}
              exit 0
            fi

            # Check if AWS cert-auth is already working
            if ${checkAwsCert}/bin/check-aws-cert >/dev/null 2>&1; then
              ${util.log.debug "aws-cert-setup-prompt: cert-auth already working"}
              exit 0
            fi

            _cert="$STACKPANEL_STATE_DIR/step/device-root.chain.crt"
            _key="$STACKPANEL_STATE_DIR/step/device.key"

            # Check if Step CA cert exists first
            if [[ ! -f "$_cert" || ! -f "$_key" ]]; then
              # Step CA not set up yet - don't prompt, let the Step CA module handle it
              ${util.log.debug "aws-cert-setup-prompt: Step CA cert not found, skipping"}
              exit 0
            fi

            ${util.log.debug "aws-cert-setup-prompt: showing interactive prompt"}

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
                mkdir -p "$STACKPANEL_STATE_DIR/aws"
                touch "$_skip_file"
                ${pkgs.gum}/bin/gum style --foreground 245 \
                  "Got it! You can run 'check-aws-cert' manually when ready."
                ${pkgs.gum}/bin/gum style --foreground 245 \
                  "To re-enable prompts, delete: \$_skip_file"
                ;;
              *)
                ${pkgs.gum}/bin/gum style --foreground 245 \
                  "Skipped. Run 'check-aws-cert' to verify setup."
                ;;
            esac
      '';
    in
    {
      stackpanel.devshell.packages = awsScripts.allPackages ++ [
        pkgs.gum
        checkAwsCert
        interactiveSetup
        # Wrapped chamber with AWS credentials baked in
        (awsScripts.wrapPackage pkgs.chamber)
      ];

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
      stackpanel.motd.features = [ "AWS Roles Anywhere (${cfg.role-name})" ];

      # Set base AWS env vars (AWS_CONFIG_FILE is set in hooks with absolute path)
      stackpanel.devshell.env = awsScripts.env;

      stackpanel.devshell.hooks.main = [
        ''
          ${util.log.debug "aws: hook starting"}
          # Set AWS_CONFIG_FILE using STACKPANEL_STATE_DIR (absolute, works in Docker too)
          export AWS_CONFIG_FILE="$STACKPANEL_STATE_DIR/aws/config"
          ${util.log.debug "aws: AWS_CONFIG_FILE=$AWS_CONFIG_FILE"}

          # Export cert paths for the credential-process script
          export AWS_CERT_PATH="$STACKPANEL_STATE_DIR/step/device-root.chain.crt"
          export AWS_KEY_PATH="$STACKPANEL_STATE_DIR/step/device.key"

          # Generate AWS config with credential_process for auto-refresh
          if [[ -f "$AWS_CERT_PATH" && -f "$AWS_KEY_PATH" ]]; then
            ${util.log.debug "aws: Step CA cert found, generating AWS config"}
            mkdir -p "$STACKPANEL_STATE_DIR/aws"
            ${awsScripts.generateAwsConfig}/bin/aws-generate-config "$AWS_CONFIG_FILE" 2>/dev/null || true
            ${util.log.debug "aws: AWS config generated at $AWS_CONFIG_FILE"}
          else
            : # Step CA cert not found, skipping AWS config generation
            ${util.log.debug "aws: Step CA cert not found, skipping AWS config generation"}
          fi


          ${util.log.debug "aws: hook complete"}
        ''
      ];

      # Register TUI prompt for post-shell-entry setup
      stackpanel.tui.prompts.aws-setup = lib.mkIf cfg.prompt-on-shell {
        enable = true;
        description = "AWS Roles Anywhere setup";
        script = ''
          ${interactiveSetup}/bin/aws-cert-setup-prompt
        '';
        delay = 0.3;
        order = 50;
      };
    }
  );
}
