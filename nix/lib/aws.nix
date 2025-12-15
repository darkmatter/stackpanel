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
    # Directory where certs/keys are stored
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
    certPath = "${stateDir}/device-root.chain.crt";
    keyPath = "${stateDir}/device.key";
    cacheFile = "${stateDir}/.aws-creds-cache.json";

    awsCredsEnv = pkgs.writeShellScriptBin "aws-creds-env" ''
      set -euo pipefail

      fetch_fresh_creds() {
        ${pkgs.aws-signing-helper}/bin/aws_signing_helper credential-process \
          --certificate "${certPath}" \
          --private-key "${keyPath}" \
          --role-arn "arn:aws:iam::${accountId}:role/${roleName}" \
          --trust-anchor-arn "${trustAnchorArn}" \
          --profile-arn "${profileArn}"
      }

      use_cache=false
      if [[ -f "${cacheFile}" ]]; then
        expiration=$(${pkgs.jq}/bin/jq -r '.Expiration // empty' "${cacheFile}" 2>/dev/null || true)
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
        creds=$(cat "${cacheFile}")
      else
        creds=$(fetch_fresh_creds)
        mkdir -p "$(dirname "${cacheFile}")"
        echo "$creds" > "${cacheFile}"
        chmod 600 "${cacheFile}"
      fi

      echo "AWS_ACCESS_KEY_ID=$(echo "$creds" | ${pkgs.jq}/bin/jq -r '.AccessKeyId')"
      echo "AWS_SECRET_ACCESS_KEY=$(echo "$creds" | ${pkgs.jq}/bin/jq -r '.SecretAccessKey')"
      echo "AWS_SESSION_TOKEN=$(echo "$creds" | ${pkgs.jq}/bin/jq -r '.SessionToken')"
      echo "AWS_REGION=${region}"
    '';

    awsCli = pkgs.writeShellScriptBin "aws" ''
      eval "$(${awsCredsEnv}/bin/aws-creds-env)"
      exec ${pkgs.awscli2}/bin/aws "$@"
    '';
  in {
    inherit awsCredsEnv awsCli;
    # Additional packages needed
    requiredPackages = [pkgs.aws-signing-helper pkgs.chamber];
    # All packages together
    allPackages = [awsCredsEnv awsCli pkgs.aws-signing-helper pkgs.chamber];
    # Environment variables to set
    env = {AWS_REGION = region;};
  };
}
