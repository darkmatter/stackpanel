# AWS cert-auth utilities - pure functions that work with any Nix module system
#
# Usage:
#   let awsLib = import ./lib/aws.nix { inherit pkgs lib; };
#   in awsLib.mkAwsCredScripts { ... }
#
{
  pkgs,
  lib,
}: {
  # Create AWS credential helper scripts
  # Returns an attrset of derivations that can be added to packages
  mkAwsCredScripts = {
    # Base state directory (e.g., .stackpanel/state)
    # AWS will use stateDir/aws, Step certs are in stateDir/step
    stateDir,
    # AWS account ID
    accountId,
    # IAM role name to assume
    roleName,
    # AWS Roles Anywhere trust anchor ARN
    trustAnchorArn,
    # AWS Roles Anywhere profile ARN
    profileArn,
    # AWS region
    region ? "us-west-2",
    # Seconds before expiry to refresh cached credentials
    cacheBufferSeconds ? "300",
  }: let
    # Derived paths (defaults, can be overridden via STACKPANEL_STATE_DIR at runtime)
    awsCacheDir = "${stateDir}/aws";
    stepStateDir = "${stateDir}/step";
    # Step CA stores certs directly in step/, not in subdirectories
    certPath = "${stepStateDir}/device-root.chain.crt";
    keyPath = "${stepStateDir}/device.key";

    # Helper to resolve state directory at runtime
    getAwsStateDir = ''
      _state_dir="''${STACKPANEL_STATE_DIR:-${stateDir}}"
      _aws_state_dir="$_state_dir/aws"
      _step_state_dir="$_state_dir/step"
      _cert_path="$_step_state_dir/device-root.chain.crt"
      _key_path="$_step_state_dir/device.key"
      _cache_file="$_aws_state_dir/.aws-creds-cache.json"
    '';

    awsCredsEnv = pkgs.writeShellScriptBin "aws-creds-env" ''
      # syntax: bash
      set -euo pipefail

      ${getAwsStateDir}

      # Pre-flight checks for certificate existence
      if [[ ! -f "$_cert_path" ]]; then
        echo "ERROR: Device certificate not found at $_cert_path" >&2
        echo "Run 'ensure-device-cert' first to obtain a certificate from Step CA." >&2
        exit 1
      fi

      if [[ ! -f "$_key_path" ]]; then
        echo "ERROR: Device private key not found at $_key_path" >&2
        echo "Run 'ensure-device-cert' first to obtain a certificate from Step CA." >&2
        exit 1
      fi

      # Verify certificate is not expired (basic check)
      if ! ${pkgs.openssl}/bin/openssl x509 -in "$_cert_path" -noout -checkend 0 >/dev/null 2>&1; then
        echo "ERROR: Device certificate at $_cert_path is expired." >&2
        echo "Run 'renew-device-cert' or 'ensure-device-cert' to obtain a new certificate." >&2
        # Invalidate cache since cert is expired
        rm -f "$_cache_file" 2>/dev/null || true
        exit 1
      fi

      fetch_fresh_creds() {
        ${pkgs.aws-signing-helper}/bin/aws_signing_helper credential-process \
          --certificate "$_cert_path" \
          --private-key "$_key_path" \
          --role-arn "arn:aws:iam::${accountId}:role/${roleName}" \
          --trust-anchor-arn "${trustAnchorArn}" \
          --profile-arn "${profileArn}"
      }

      use_cache=false
      if [[ -f "$_cache_file" ]]; then
        expiration=$(${pkgs.jq}/bin/jq -r '.Expiration // empty' "$_cache_file" 2>/dev/null || true)
        if [[ -n "$expiration" ]]; then
          if exp_epoch=$(date -d "$expiration" +%s 2>/dev/null) || \
             exp_epoch=$(date -jf "%Y-%m-%dT%H:%M:%SZ" "$expiration" +%s 2>/dev/null); then
            now_epoch=$(date +%s)
            if (( exp_epoch - now_epoch > ${cacheBufferSeconds} )); then
              use_cache=true
            fi
          fi
        fi
      fi

      if $use_cache; then
        creds=$(cat "$_cache_file")
      else
        creds=$(fetch_fresh_creds)
        mkdir -p "$(dirname "$_cache_file")"
        echo "$creds" > "$_cache_file"
        chmod 600 "$_cache_file"
      fi

      echo "export AWS_ACCESS_KEY_ID=$(echo "$creds" | ${pkgs.jq}/bin/jq -r '.AccessKeyId')"
      echo "export AWS_SECRET_ACCESS_KEY=$(echo "$creds" | ${pkgs.jq}/bin/jq -r '.SecretAccessKey')"
      echo "export AWS_SESSION_TOKEN=$(echo "$creds" | ${pkgs.jq}/bin/jq -r '.SessionToken')"
      echo "export AWS_REGION=${region}"
    '';

    awsCli = pkgs.writeShellScriptBin "aws" ''
      eval "$(${awsCredsEnv}/bin/aws-creds-env)"
      exec ${pkgs.awscli2}/bin/aws "$@"
    '';

    # Credential process script for use in AWS config files / Docker
    # This is called by the AWS SDK to get fresh credentials on demand
    credentialProcess = pkgs.writeShellScriptBin "aws-credential-process" ''
      set -euo pipefail

      # Resolve state directory at runtime for Docker portability
      _state_dir="''${STACKPANEL_STATE_DIR:-${stateDir}}"
      _cert_path="$_state_dir/step/device-root.chain.crt"
      _key_path="$_state_dir/step/device.key"

      exec ${pkgs.aws-signing-helper}/bin/aws_signing_helper credential-process \
        --certificate "$_cert_path" \
        --private-key "$_key_path" \
        --role-arn "arn:aws:iam::${accountId}:role/${roleName}" \
        --trust-anchor-arn "${trustAnchorArn}" \
        --profile-arn "${profileArn}"
    '';

    # Generate an AWS config file that uses credential_process
    # Mount this into Docker containers along with the cert/key
    generateAwsConfig = pkgs.writeShellScriptBin "aws-generate-config" ''
      # syntax: bash
      set -euo pipefail

      OUTPUT="''${1:-/dev/stdout}"

      # Resolve state directory at runtime for Docker portability
      _state_dir="''${STACKPANEL_STATE_DIR:-${stateDir}}"
      _cert_path="$_state_dir/step/device-root.chain.crt"
      _key_path="$_state_dir/step/device.key"

      CERT_PATH="''${AWS_CERT_PATH:-$_cert_path}"
      KEY_PATH="''${AWS_KEY_PATH:-$_key_path}"
      SIGNING_HELPER="''${AWS_SIGNING_HELPER:-${pkgs.aws-signing-helper}/bin/aws_signing_helper}"

      cat > "$OUTPUT" << EOF
      [default]
      region = ${region}
      credential_process = $SIGNING_HELPER credential-process --certificate $CERT_PATH --private-key $KEY_PATH --role-arn arn:aws:iam::${accountId}:role/${roleName} --trust-anchor-arn ${trustAnchorArn} --profile-arn ${profileArn}
      EOF

      # Remove leading whitespace from heredoc
      if [[ "$OUTPUT" != "/dev/stdout" ]]; then
        sed -i.bak 's/^      //' "$OUTPUT" && rm -f "$OUTPUT.bak"
        chmod 600 "$OUTPUT"
      fi
    '';

    # Helper to run any command with AWS creds
    withAws = pkgs.writeShellScriptBin "with-aws" ''
      eval "$(${awsCredsEnv}/bin/aws-creds-env)"
      exec "$@"
    '';
  in {
    inherit awsCredsEnv awsCli credentialProcess generateAwsConfig withAws;
    # Additional packages needed
    requiredPackages = [pkgs.aws-signing-helper pkgs.chamber pkgs.openssl];
    # All packages together
    allPackages = [awsCredsEnv awsCli credentialProcess generateAwsConfig withAws pkgs.aws-signing-helper pkgs.chamber];
    # Environment variables - use credential_process config for auto-refresh
    # The config file must be generated on shell entry
    env = {
      AWS_REGION = region;
      AWS_SHARED_CREDENTIALS_FILE = "/dev/null";
    };
    # Config file path for credential_process (relative, resolved at runtime via STACKPANEL_STATE_DIR)
    configPath = "${stateDir}/aws/config";
    # Paths for Docker mounting (relative, resolved at runtime via STACKPANEL_STATE_DIR)
    paths = {
      cert = "${stateDir}/step/device-root.chain.crt";
      key = "${stateDir}/step/device.key";
      stateDir = stateDir;
    };
  };
}
