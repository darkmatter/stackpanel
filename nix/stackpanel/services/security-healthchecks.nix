# ==============================================================================
# security-healthchecks.nix
#
# Healthchecks for security-related modules:
#   - Step CA: Verify certificate generation and validity
#   - AWS Roles Anywhere: Verify role assumption works
#   - SOPS: Verify secret decryption works
#
# These healthchecks validate that the security infrastructure is properly
# configured and functional, providing traffic light indicators in the UI.
#
# NOTE: Scripts use PATH commands (not Nix store paths) since they run
# via `sh -c` in the Go agent. Commands like openssl, curl, aws, jq, sops
# must be available in the devshell PATH.
# ==============================================================================
{
  lib,
  config,
  ...
}:
let
  # Module configurations
  stepCfg = config.stackpanel.step-ca or { enable = false; };
  awsCfg = config.stackpanel.aws.roles-anywhere or { enable = false; };
  secretsCfg = config.stackpanel.secrets or { enable = false; };
  healthchecksCfg = config.stackpanel.healthchecks or { enable = true; };
in
{
  config = lib.mkIf healthchecksCfg.enable {
    # =========================================================================
    # Step CA Healthchecks
    # =========================================================================
    stackpanel.healthchecks.modules.step-ca = lib.mkIf stepCfg.enable {
      enable = true;
      displayName = "Step CA";
      checks = {
        cert-exists = {
          name = "Certificate Exists";
          description = "Check if device certificate and key files exist";
          type = "script";
          severity = "critical";
          timeout = 5;
          script = ''
            CERT_PATH="$STACKPANEL_STATE_DIR/step/device-root.chain.crt"
            KEY_PATH="$STACKPANEL_STATE_DIR/step/device.key"

            if [ ! -f "$CERT_PATH" ]; then
              echo "Certificate not found at: $CERT_PATH"
              echo "Run 'ensure-device-cert' to generate a certificate"
              exit 1
            fi

            if [ ! -f "$KEY_PATH" ]; then
              echo "Private key not found at: $KEY_PATH"
              exit 1
            fi

            echo "Certificate and key files exist"
          '';
        };

        cert-valid = {
          name = "Certificate Valid";
          description = "Check if the device certificate is valid and not expired";
          type = "script";
          severity = "critical";
          timeout = 10;
          script = ''
            CERT_PATH="$STACKPANEL_STATE_DIR/step/device-root.chain.crt"

            if [ ! -f "$CERT_PATH" ]; then
              echo "Certificate not found"
              exit 1
            fi

            # Check certificate expiration
            if ! openssl x509 -checkend 0 -noout -in "$CERT_PATH" 2>/dev/null; then
              expiry=$(openssl x509 -enddate -noout -in "$CERT_PATH" 2>/dev/null | cut -d= -f2)
              echo "Certificate has expired: $expiry"
              echo "Run 'ensure-device-cert' to regenerate"
              exit 1
            fi

            # Get expiry date for info
            expiry=$(openssl x509 -enddate -noout -in "$CERT_PATH" 2>/dev/null | cut -d= -f2)
            echo "Certificate valid until: $expiry"
          '';
        };

        cert-expiry-warning = {
          name = "Certificate Expiry Warning";
          description = "Warn if certificate expires within 7 days";
          type = "script";
          severity = "warning";
          timeout = 10;
          script = ''
            CERT_PATH="$STACKPANEL_STATE_DIR/step/device-root.chain.crt"

            if [ ! -f "$CERT_PATH" ]; then
              echo "Certificate not found"
              exit 1
            fi

            # Check if cert expires within 7 days (604800 seconds)
            if ! openssl x509 -checkend 604800 -noout -in "$CERT_PATH" 2>/dev/null; then
              expiry=$(openssl x509 -enddate -noout -in "$CERT_PATH" 2>/dev/null | cut -d= -f2)
              echo "Certificate expires soon: $expiry"
              echo "Consider running 'ensure-device-cert' to regenerate"
              exit 1
            fi

            echo "Certificate has more than 7 days validity"
          '';
        };

        ca-reachable = lib.mkIf (stepCfg.ca-url or "" != "") {
          name = "CA Reachable";
          description = "Check if the Step CA server is reachable";
          type = "script";
          severity = "warning";
          timeout = 15;
          script = ''
            CA_URL="${stepCfg.ca-url or ""}"

            if [ -z "$CA_URL" ]; then
              echo "CA URL not configured"
              exit 1
            fi

            # Extract host and port from URL
            host_port=$(echo "$CA_URL" | sed 's|^https\?://||' | sed 's|/.*||')
            host=$(echo "$host_port" | cut -d: -f1)
            port=$(echo "$host_port" | grep -o ':[0-9]*$' | tr -d ':')
            port=''${port:-443}

            # Try to connect using curl (we don't verify the cert here, just connectivity)
            if curl -sSf -o /dev/null --connect-timeout 5 -k "$CA_URL/health" 2>/dev/null; then
              echo "Step CA at $CA_URL is reachable"
            elif curl -sSf -o /dev/null --connect-timeout 5 -k "$CA_URL" 2>/dev/null; then
              echo "Step CA at $CA_URL is reachable"
            else
              # Fall back to nc/timeout check if available
              if command -v nc >/dev/null 2>&1; then
                if nc -z -w 5 "$host" "$port" 2>/dev/null; then
                  echo "Step CA at $host:$port is reachable (TCP)"
                else
                  echo "Cannot reach Step CA at $CA_URL"
                  exit 1
                fi
              else
                echo "Cannot reach Step CA at $CA_URL"
                exit 1
              fi
            fi
          '';
        };
      };
    };

    # =========================================================================
    # AWS Roles Anywhere Healthchecks
    # =========================================================================
    stackpanel.healthchecks.modules.aws-roles-anywhere = lib.mkIf awsCfg.enable {
      enable = true;
      displayName = "AWS Roles Anywhere";
      checks = {
        step-cert-available = {
          name = "Step CA Certificate Available";
          description = "Check if device certificate is available for AWS auth";
          type = "script";
          severity = "critical";
          timeout = 5;
          script = ''
            CERT_PATH="''${AWS_CERT_PATH:-$STACKPANEL_STATE_DIR/step/device-root.chain.crt}"
            KEY_PATH="''${AWS_KEY_PATH:-$STACKPANEL_STATE_DIR/step/device.key}"

            if [ ! -f "$CERT_PATH" ]; then
              echo "Device certificate not found at: $CERT_PATH"
              echo "AWS Roles Anywhere requires a valid Step CA certificate"
              echo "Run 'ensure-device-cert' first"
              exit 1
            fi

            if [ ! -f "$KEY_PATH" ]; then
              echo "Device private key not found at: $KEY_PATH"
              exit 1
            fi

            echo "Device certificate available for AWS auth"
          '';
        };

        assume-role = {
          name = "Assume Role";
          description = "Test that we can assume the configured AWS role";
          type = "script";
          severity = "critical";
          timeout = 30;
          script = ''
            CERT_PATH="''${AWS_CERT_PATH:-$STACKPANEL_STATE_DIR/step/device-root.chain.crt}"
            KEY_PATH="''${AWS_KEY_PATH:-$STACKPANEL_STATE_DIR/step/device.key}"

            # Check prerequisites
            if [ ! -f "$CERT_PATH" ] || [ ! -f "$KEY_PATH" ]; then
              echo "Device certificate not available"
              echo "Run 'ensure-device-cert' first"
              exit 1
            fi

            # Check if certificate is valid
            if ! openssl x509 -checkend 0 -noout -in "$CERT_PATH" 2>/dev/null; then
              echo "Device certificate has expired"
              echo "Run 'ensure-device-cert' to regenerate"
              exit 1
            fi

            # Try to get caller identity using AWS CLI
            # This will trigger the credential_process if configured
            if aws sts get-caller-identity >/dev/null 2>&1; then
              identity=$(aws sts get-caller-identity --output json 2>/dev/null)
              account=$(echo "$identity" | jq -r '.Account // "unknown"')
              arn=$(echo "$identity" | jq -r '.Arn // "unknown"')
              echo "Successfully assumed role"
              echo "Account: $account"
              echo "ARN: $arn"
            else
              echo "Failed to assume AWS role via Roles Anywhere"
              echo ""
              echo "Troubleshooting:"
              echo "  1. Verify Step CA certificate is valid and trusted"
              echo "  2. Check trust anchor ARN: ${awsCfg.trust-anchor-arn or "not configured"}"
              echo "  3. Check profile ARN: ${awsCfg.profile-arn or "not configured"}"
              echo "  4. Check role name: ${awsCfg.role-name or "not configured"}"
              echo ""
              echo "Run 'check-aws-cert' for detailed diagnostics"
              exit 1
            fi
          '';
        };

        config-complete = {
          name = "Configuration Complete";
          description = "Verify all required AWS Roles Anywhere settings are configured";
          type = "script";
          severity = "warning";
          timeout = 5;
          script = ''
            errors=0

            check_config() {
              local name="$1"
              local value="$2"
              if [ -z "$value" ] || [ "$value" = "null" ]; then
                echo "Missing: $name"
                errors=$((errors + 1))
              fi
            }

            check_config "account-id" "${awsCfg.account-id or ""}"
            check_config "role-name" "${awsCfg.role-name or ""}"
            check_config "trust-anchor-arn" "${awsCfg.trust-anchor-arn or ""}"
            check_config "profile-arn" "${awsCfg.profile-arn or ""}"
            check_config "region" "${awsCfg.region or ""}"

            if [ $errors -gt 0 ]; then
              echo ""
              echo "$errors configuration item(s) missing"
              echo "Configure in .stackpanel/config.nix under aws.roles-anywhere"
              exit 1
            fi

            echo "All required settings configured"
            echo "Account: ${awsCfg.account-id or "?"}"
            echo "Role: ${awsCfg.role-name or "?"}"
            echo "Region: ${awsCfg.region or "?"}"
          '';
        };
      };
    };

    # =========================================================================
    # SOPS / Secrets Healthchecks
    # =========================================================================
    stackpanel.healthchecks.modules.sops = lib.mkIf secretsCfg.enable {
      enable = true;
      displayName = "SOPS Secrets";
      checks = {
        sops-installed = {
          name = "SOPS Available";
          description = "Check if SOPS binary is available";
          type = "script";
          severity = "critical";
          timeout = 5;
          script = ''
            if command -v sops >/dev/null 2>&1; then
              version=$(sops --version 2>&1 | head -1)
              echo "SOPS is available: $version"
            else
              echo "SOPS binary not found in PATH"
              exit 1
            fi
          '';
        };

        age-key-available = {
          name = "AGE Key Available";
          description = "Check if an AGE key is available for decryption";
          type = "script";
          severity = "critical";
          timeout = 5;
          script = ''
            # Check common AGE key locations
            found=0

            # Check SOPS_AGE_KEY_FILE first
            if [ -n "$SOPS_AGE_KEY_FILE" ] && [ -f "$SOPS_AGE_KEY_FILE" ]; then
              echo "AGE key found at: $SOPS_AGE_KEY_FILE"
              exit 0
            fi

            # Check stackpanel state dir
            if [ -f "$STACKPANEL_STATE_DIR/age-key.txt" ]; then
              echo "AGE key found at: $STACKPANEL_STATE_DIR/age-key.txt"
              exit 0
            fi

            # Check standard locations
            for loc in "$HOME/.config/sops/age/keys.txt" "$HOME/.age/keys.txt" "$HOME/.config/age/keys.txt"; do
              if [ -f "$loc" ]; then
                echo "AGE key found at: $loc"
                exit 0
              fi
            done

            echo "No AGE key found"
            echo ""
            echo "Checked locations:"
            if [ -n "$SOPS_AGE_KEY_FILE" ]; then
              echo "  - \$SOPS_AGE_KEY_FILE ($SOPS_AGE_KEY_FILE)"
            else
              echo "  - \$SOPS_AGE_KEY_FILE (not set)"
            fi
            echo "  - \$STACKPANEL_STATE_DIR/age-key.txt"
            echo "  - ~/.config/sops/age/keys.txt"
            echo "  - ~/.age/keys.txt"
            echo "  - ~/.config/age/keys.txt"
            echo ""
            echo "Generate a key with: age-keygen -o ~/.config/sops/age/keys.txt"
            echo "Or enable auto-generate in stackpanel.secrets.auto-generate-key"
            exit 1
          '';
        };

        sops-yaml-exists = {
          name = "SOPS Config Exists";
          description = "Check if .sops.yaml configuration file exists";
          type = "script";
          severity = "warning";
          timeout = 5;
          script = ''
            if [ -f ".sops.yaml" ]; then
              echo ".sops.yaml found"
              # Count creation rules
              rules=$(grep -c "creation_rule" .sops.yaml 2>/dev/null || echo "0")
              echo "Creation rules: $rules"
            else
              echo ".sops.yaml not found"
              echo "Generate with the Stackpanel UI or manually create it"
              exit 1
            fi
          '';
        };

        decrypt-test = {
          name = "Decrypt Test";
          description = "Test decrypting an encrypted secret file";
          type = "script";
          severity = "warning";
          timeout = 15;
          script = ''
            # Find a SOPS-encrypted file to test
            test_file=""

            # Look for common encrypted file patterns
            for pattern in ".stackpanel/secrets/"*.enc.json ".stackpanel/secrets/"*.sops.json \
                           ".stackpanel/secrets/"*.enc.yaml ".stackpanel/secrets/"*.sops.yaml \
                           "secrets/"*.enc.json "secrets/"*.sops.json; do
              for f in $pattern; do
                if [ -f "$f" ]; then
                  test_file="$f"
                  break 2
                fi
              done
            done

            if [ -z "$test_file" ]; then
              echo "No encrypted secret files found to test"
              echo "This is OK if you haven't created any secrets yet"
              exit 0
            fi

            echo "Testing decryption of: $test_file"

            # Try to decrypt (just validate, don't output secrets)
            if sops --decrypt "$test_file" >/dev/null 2>&1; then
              echo "Successfully decrypted $test_file"
            else
              echo "Failed to decrypt $test_file"
              echo ""
              echo "Possible causes:"
              echo "  1. Your AGE key is not in the file's recipients"
              echo "  2. KMS key not accessible (if using KMS)"
              echo "  3. File is corrupted"
              echo ""
              echo "Run: sops --decrypt \"$test_file\" for details"
              exit 1
            fi
          '';
        };

        kms-access = lib.mkIf ((secretsCfg.kms or { enable = false; }).enable or false) {
          name = "KMS Access";
          description = "Verify access to configured AWS KMS key";
          type = "script";
          severity = "warning";
          timeout = 20;
          script = ''
            KMS_ARN="${(secretsCfg.kms or { }).arn or ""}"

            if [ -z "$KMS_ARN" ]; then
              echo "KMS ARN not configured"
              exit 1
            fi

            echo "Testing KMS key: $KMS_ARN"

            # Try to describe the key
            if aws kms describe-key --key-id "$KMS_ARN" >/dev/null 2>&1; then
              echo "KMS key is accessible"

              # Try a test encryption
              if echo "healthcheck-test" | aws kms encrypt \
                  --key-id "$KMS_ARN" \
                  --plaintext fileb:///dev/stdin \
                  --output text \
                  --query CiphertextBlob >/dev/null 2>&1; then
                echo "KMS encryption test passed"
              else
                echo "Warning: Could not test KMS encryption"
                echo "You may not have kms:Encrypt permission"
                exit 1
              fi
            else
              echo "Cannot access KMS key"
              echo ""
              echo "Ensure you have the following permissions:"
              echo "  - kms:DescribeKey"
              echo "  - kms:Encrypt"
              echo "  - kms:Decrypt"
              exit 1
            fi
          '';
        };
      };
    };
  };
}
