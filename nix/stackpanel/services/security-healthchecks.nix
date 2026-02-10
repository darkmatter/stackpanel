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

  # Secrets groups for per-group checks
  secretsGroups = secretsCfg.groups or { };
  secretsDir = secretsCfg.secrets-dir or ".stackpanel/secrets";

  # Infra config for checking if KMS/IAM is deployed
  infraCfg = config.stackpanel.infra or { enable = false; };
  infraAwsSecrets = infraCfg.aws.secrets or { enable = false; };

  # Generate per-group SSM access healthchecks.
  # Each group stores its AGE private key in SSM. This check verifies
  # that the current AWS credentials can read that parameter.
  # Red = AWS/SSM not set up or no permissions for the group's key path.
  groupSsmChecks = lib.mapAttrs' (
    name: group:
    lib.nameValuePair "ssm-access-${name}" {
      name = "SSM Access: ${name}";
      description = "Check if the group key for '${name}' is readable from SSM at ${group.ssm-path}";
      type = "script";
      severity = "warning";
      timeout = 15;
      script = ''
        SSM_PATH="${group.ssm-path}"

        if ! command -v aws >/dev/null 2>&1; then
          echo "AWS CLI not found in PATH"
          echo "Install awscli2 or ensure it's in the devshell"
          exit 1
        fi

        # Try to read the parameter (just verify access, don't output the secret)
        if aws ssm get-parameter --name "$SSM_PATH" --with-decryption --query "Parameter.Name" --output text >/dev/null 2>&1; then
          echo "SSM parameter accessible: $SSM_PATH"
        else
          # Try to distinguish between "not found" and "access denied"
          error=$(aws ssm get-parameter --name "$SSM_PATH" --with-decryption 2>&1 || true)
          if echo "$error" | grep -qi "ParameterNotFound"; then
            echo "SSM parameter not found: $SSM_PATH"
            echo ""
            echo "The group key has not been stored in SSM yet."
            echo "Run: secrets:init-group ${name}"
          elif echo "$error" | grep -qi "ExpiredTokenException\|AccessDenied\|UnrecognizedClient\|InvalidSignature"; then
            echo "AWS credentials not configured or insufficient permissions"
            echo ""
            echo "Ensure you have ssm:GetParameter permission for: $SSM_PATH"
          else
            echo "Cannot access SSM parameter: $SSM_PATH"
            echo "$error"
          fi
          exit 1
        fi
      '';
    }
  ) secretsGroups;

  # Generate per-group key file existence checks.
  # Each group's AGE private key should be stored as a SOPS-encrypted
  # .enc.age file in the keys/ directory.
  groupKeyFileChecks = lib.mapAttrs' (
    name: _group:
    lib.nameValuePair "group-key-exists-${name}" {
      name = "Group Key Exists: ${name}";
      description = "Check if the encrypted AGE key file exists for group '${name}'";
      type = "script";
      severity = "critical";
      timeout = 5;
      tags = [
        "secrets"
        "groups"
        "keys"
      ];
      script = ''
        ENC_AGE_FILE="${secretsDir}/keys/${name}.enc.age"

        if [ -f "$ENC_AGE_FILE" ]; then
          # Verify it's not empty
          if [ -s "$ENC_AGE_FILE" ]; then
            echo "Group key file exists: $ENC_AGE_FILE"
            size=$(wc -c < "$ENC_AGE_FILE" | tr -d ' ')
            echo "Size: $size bytes"
          else
            echo "Group key file is empty: $ENC_AGE_FILE"
            echo ""
            echo "Re-initialize with: secrets:init-group ${name}"
            exit 1
          fi
        else
          echo "Group key file not found: $ENC_AGE_FILE"
          echo ""
          echo "The encrypted AGE private key for group '${name}' has not been created."
          echo "Initialize with: secrets:init-group ${name}"
          exit 1
        fi
      '';
    }
  ) secretsGroups;

  # Generate per-group decrypt checks.
  # For each group that has a SOPS-encrypted secrets file, verify we can
  # actually decrypt it using the group key chain.
  groupDecryptChecks = lib.mapAttrs' (
    name: _group:
    lib.nameValuePair "group-decrypt-${name}" {
      name = "Decrypt Group: ${name}";
      description = "Test decrypting the '${name}' group secrets file using the group key";
      type = "script";
      severity = "warning";
      timeout = 20;
      tags = [
        "secrets"
        "groups"
        "decrypt"
      ];
      script = ''
        GROUP_FILE="${secretsDir}/groups/${name}.yaml"

        if [ ! -f "$GROUP_FILE" ]; then
          echo "No secrets file for group '${name}' at $GROUP_FILE"
          echo "This is OK if you haven't added secrets to this group yet"
          exit 0
        fi

        # Check that the .enc.age key file exists first
        ENC_AGE_FILE="${secretsDir}/keys/${name}.enc.age"
        if [ ! -f "$ENC_AGE_FILE" ]; then
          echo "Cannot decrypt: group key not found at $ENC_AGE_FILE"
          echo "Initialize with: secrets:init-group ${name}"
          exit 1
        fi

        echo "Testing decryption of: $GROUP_FILE"

        # Try to decrypt (validate only, don't output secrets)
        if sops --decrypt "$GROUP_FILE" >/dev/null 2>&1; then
          echo "Successfully decrypted $GROUP_FILE"
        else
          echo "Failed to decrypt $GROUP_FILE"
          echo ""
          echo "Possible causes:"
          echo "  1. Local AGE key cannot decrypt the group .enc.age file"
          echo "  2. Group key is not in the secrets file's recipients"
          echo "  3. SOPS_AGE_KEY_CMD is not configured correctly"
          echo ""
          echo "Try manually: sops --decrypt \"$GROUP_FILE\""
          exit 1
        fi
      '';
    }
  ) secretsGroups;
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
        # Per-group checks (dynamically generated from secrets.groups)
      }
      // groupSsmChecks
      // groupKeyFileChecks
      // groupDecryptChecks
      // {
        sops-installed = {
          name = "SOPS Available";
          description = "Check if SOPS binary is available";
          type = "script";
          severity = "critical";
          timeout = 5;
          tags = [
            "secrets"
            "toolchain"
          ];
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
          tags = [
            "secrets"
            "keys"
          ];
          script = ''
            # Check common AGE key locations
            found=0

            # Check SOPS_AGE_KEY_CMD first (lazy key command)
            if [ -n "$SOPS_AGE_KEY_CMD" ]; then
              echo "AGE key command configured: $SOPS_AGE_KEY_CMD"
              exit 0
            fi

            # Check SOPS_AGE_KEY_FILE
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
            echo "  - \$SOPS_AGE_KEY_CMD (not set)"
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
          tags = [
            "secrets"
            "config"
          ];
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

        kms-access = lib.mkIf ((secretsCfg.kms or { enable = false; }).enable or false) {
          name = "KMS Access";
          description = "Verify access to configured AWS KMS key";
          type = "script";
          severity = "warning";
          timeout = 20;
          tags = [
            "secrets"
            "kms"
            "aws"
          ];
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

        # =====================================================================
        # Infra Deployed: verify KMS key + IAM role are provisioned
        # =====================================================================
        infra-deployed = lib.mkIf (infraAwsSecrets.enable or false) {
          name = "Secrets Infra Deployed";
          description = "Verify that Alchemy-provisioned KMS key and IAM role exist in AWS";
          type = "script";
          severity = "warning";
          timeout = 30;
          tags = [
            "secrets"
            "infra"
            "alchemy"
            "aws"
          ];
          script = ''
            KMS_ALIAS="alias/${infraAwsSecrets.kms.alias or "stackpanel-secrets"}"
            ROLE_NAME="${infraAwsSecrets.iam.role-name or "stackpanel-secrets-role"}"
            REGION="${infraAwsSecrets.region or "us-west-2"}"
            errors=0

            if ! command -v aws >/dev/null 2>&1; then
              echo "AWS CLI not found in PATH"
              echo "Install awscli2 or ensure it's in the devshell"
              exit 1
            fi

            # Check AWS credentials
            if ! aws sts get-caller-identity >/dev/null 2>&1; then
              echo "AWS credentials not available"
              echo ""
              echo "Authenticate first (e.g., ensure-device-cert for Roles Anywhere)"
              exit 1
            fi

            # Check KMS key exists via alias
            echo "Checking KMS key: $KMS_ALIAS"
            if aws kms describe-key --key-id "$KMS_ALIAS" --region "$REGION" >/dev/null 2>&1; then
              key_state=$(aws kms describe-key --key-id "$KMS_ALIAS" --region "$REGION" --query "KeyMetadata.KeyState" --output text 2>/dev/null)
              echo "KMS key exists (state: $key_state)"
              if [ "$key_state" != "Enabled" ]; then
                echo "Warning: KMS key is not in Enabled state"
                errors=$((errors + 1))
              fi
            else
              echo "KMS key not found: $KMS_ALIAS"
              echo "Run 'infra:deploy' to provision the KMS key"
              errors=$((errors + 1))
            fi

            # Check IAM role exists
            echo "Checking IAM role: $ROLE_NAME"
            if aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1; then
              role_arn=$(aws iam get-role --role-name "$ROLE_NAME" --query "Role.Arn" --output text 2>/dev/null)
              echo "IAM role exists: $role_arn"
            else
              echo "IAM role not found: $ROLE_NAME"
              echo "Run 'infra:deploy' to provision the IAM role"
              errors=$((errors + 1))
            fi

            if [ $errors -gt 0 ]; then
              echo ""
              echo "$errors infrastructure resource(s) missing or degraded"
              echo ""
              echo "Deploy with: infra:deploy"
              exit 1
            fi

            echo ""
            echo "All secrets infrastructure resources are deployed"
          '';
        };
      };
    };
  };
}
