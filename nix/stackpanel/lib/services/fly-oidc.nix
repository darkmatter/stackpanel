# ==============================================================================
# services/fly-oidc.nix
#
# Fly.io OIDC to AWS authentication utilities.
# Pure functions that work with any Nix module system.
#
# Creates entrypoint scripts for containers running on Fly.io that need to
# authenticate to AWS using OIDC federation. The script handles:
# - Retrieving OIDC token from Fly.io (token file or API fallback)
# - Exchanging token for AWS credentials via STS AssumeRoleWithWebIdentity
# - Optionally loading secrets from AWS SSM Parameter Store via Chamber
# - Executing the container's main command
#
# == USAGE ==
#
#   let flyOidc = import ./fly-oidc.nix { inherit pkgs; };
#
#   # Basic usage with Chamber:
#   entrypoint = flyOidc.mkEntrypoint {
#     chamberService = "myapp/prod";
#     sessionPrefix = "myapp";
#   };
#
#   # Skip Chamber, just get AWS creds:
#   entrypoint = flyOidc.mkEntrypoint {
#     sessionPrefix = "myapp";
#     skipChamber = true;
#   };
#
#   # With custom hooks:
#   entrypoint = flyOidc.mkEntrypoint {
#     chamberService = "myapp/prod";
#     sessionPrefix = "myapp";
#     postAuthHook = ''
#       echo "Running migrations..."
#       /app/migrate.sh
#     '';
#   };
#
# == CONTAINER CONFIG ==
#
#   config = {
#     entrypoint = [ "${entrypoint}/bin/fly-oidc-entrypoint" ];
#     Cmd = [ "node" "server.js" ];
#     Env = [
#       "AWS_REGION=us-west-2"
#       "AWS_ROLE_ARN=arn:aws:iam::123456789:role/myapp-prod"
#     ];
#   };
#
# == FLY.TOML ==
#
#   [env]
#   AWS_ROLE_ARN = "arn:aws:iam::123456789:role/myapp-prod"
#
# == AWS IAM TRUST POLICY ==
#
#   {
#     "Version": "2012-10-17",
#     "Statement": [{
#       "Effect": "Allow",
#       "Principal": {
#         "Federated": "arn:aws:iam::ACCOUNT:oidc-provider/oidc.fly.io/ORG"
#       },
#       "Action": "sts:AssumeRoleWithWebIdentity",
#       "Condition": {
#         "StringEquals": { "oidc.fly.io/ORG:aud": "sts.amazonaws.com" },
#         "StringLike": { "oidc.fly.io/ORG:sub": "APP_NAME:*" }
#       }
#     }]
#   }
#
# == EXPORTS ==
#
#   - mkEntrypoint: Creates a container entrypoint with OIDC auth
#   - mkEnvConfig: Helper to generate environment variables for fly.toml
#
# ==============================================================================
{
  pkgs,
  lib ? pkgs.lib,
}:
{
  # ===========================================================================
  # mkEntrypoint - Create a container entrypoint with Fly.io OIDC -> AWS auth
  # ===========================================================================
  #
  # Required arguments:
  #   sessionPrefix  - Prefix for AWS session name (e.g., "myapp")
  #
  # Optional arguments:
  #   chamberService     - Chamber service path (e.g., "myapp/prod"). Required unless skipChamber=true
  #   tokenFile          - Path to write OIDC token (default: "/tmp/fly-oidc-token")
  #   awsRegion          - AWS region (default: "us-west-2")
  #   durationSeconds    - AWS credential duration (default: 3600)
  #   maxAttempts        - Max OIDC token fetch retries (default: 10)
  #   retryDelaySecs     - Delay between retries (default: 10)
  #   fileWaitSecs       - Max wait for token file (default: 30)
  #   socketWaitSecs     - Max wait for Fly API socket (default: 60)
  #   extraRuntimeInputs - Additional packages for the entrypoint
  #   preAuthHook        - Script to run before authentication
  #   postAuthHook       - Script to run after authentication (before exec)
  #   skipChamber        - If true, export creds and run command directly (default: false)
  #   debug              - Enable verbose JWT decoding output (default: true)
  #
  mkEntrypoint =
    {
      sessionPrefix,
      chamberService ? "",
      tokenFile ? "/tmp/fly-oidc-token",
      awsRegion ? "us-west-2",
      durationSeconds ? 3600,
      maxAttempts ? 10,
      retryDelaySecs ? 10,
      fileWaitSecs ? 30,
      socketWaitSecs ? 60,
      extraRuntimeInputs ? [ ],
      preAuthHook ? "",
      postAuthHook ? "",
      skipChamber ? false,
      debug ? true,
    }:
    let
      execCommand =
        if skipChamber then
          ''exec "$@"''
        else
          ''exec ${pkgs.chamber}/bin/chamber exec ${chamberService} -- "$@"'';

      debugBlock =
        if debug then
          ''
            # Decode and display JWT token claims for debugging
            echo "==> Decoding OIDC token (JWT) for diagnostics..."
            TOKEN_PAYLOAD=$(echo "$FLY_OIDC_TOKEN" | cut -d'.' -f2)
            # Add padding if needed for base64 decoding
            case $((''${#TOKEN_PAYLOAD} % 4)) in
              2) TOKEN_PAYLOAD="''${TOKEN_PAYLOAD}==";;
              3) TOKEN_PAYLOAD="''${TOKEN_PAYLOAD}=";;
            esac
            echo "    Token claims:"
            echo "$TOKEN_PAYLOAD" | base64 -d 2>/dev/null | jq '.' 2>/dev/null || echo "    Unable to decode token payload"
          ''
        else
          "";

    in
    pkgs.writeShellApplication {
      name = "fly-oidc-entrypoint";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.jq
        pkgs.curl
        pkgs.awscli2
        pkgs.chamber
      ] ++ extraRuntimeInputs;

      text = ''
        set -euo pipefail

        ${preAuthHook}

        echo "==> Authenticating to AWS using Fly.io OIDC..."

        # Print AWS environment variables for diagnostics
        echo "==> AWS Environment Variables:"
        echo "    AWS_ROLE_ARN: ''${AWS_ROLE_ARN:-<not set>}"
        echo "    AWS_WEB_IDENTITY_TOKEN_FILE: ''${AWS_WEB_IDENTITY_TOKEN_FILE:-<not set>}"
        echo "    AWS_ROLE_SESSION_NAME: ''${AWS_ROLE_SESSION_NAME:-<not set>}"

        # Check what files exist in /.fly/
        echo "==> Checking /.fly/ directory:"
        if [ -d "/.fly" ]; then
          ls -la /.fly/ || echo "    Unable to list /.fly/"
        else
          echo "    /.fly/ directory does not exist"
        fi

        # Retry logic: attempt to get OIDC token up to N times
        MAX_ATTEMPTS=${toString maxAttempts}
        ATTEMPT=1
        FLY_OIDC_TOKEN=""

        # First, wait for the OIDC token file to be created by Fly.io
        if [ -n "''${AWS_WEB_IDENTITY_TOKEN_FILE:-}" ]; then
          echo "==> Waiting for OIDC token file at ''${AWS_WEB_IDENTITY_TOKEN_FILE}..."
          FILE_WAIT_ATTEMPTS=0
          MAX_FILE_WAIT=${toString fileWaitSecs}

          while [ $FILE_WAIT_ATTEMPTS -lt $MAX_FILE_WAIT ]; do
            if [ -f "''${AWS_WEB_IDENTITY_TOKEN_FILE}" ]; then
              echo "    OIDC token file found after ''${FILE_WAIT_ATTEMPTS} seconds"
              break
            fi
            sleep 1
            FILE_WAIT_ATTEMPTS=$((FILE_WAIT_ATTEMPTS + 1))
          done

          if [ ! -f "''${AWS_WEB_IDENTITY_TOKEN_FILE}" ]; then
            echo "    WARNING: OIDC token file not found after ''${MAX_FILE_WAIT} seconds, will try API endpoint"
          fi
        fi

        # Try reading from the file if it exists
        if [ -n "''${AWS_WEB_IDENTITY_TOKEN_FILE:-}" ] && [ -f "''${AWS_WEB_IDENTITY_TOKEN_FILE}" ]; then
          echo "==> Reading OIDC token from file at ''${AWS_WEB_IDENTITY_TOKEN_FILE}..."
          if FLY_OIDC_TOKEN=$(cat "''${AWS_WEB_IDENTITY_TOKEN_FILE}" 2>&1); then
            echo "==> Successfully read OIDC token from file (length: ''${#FLY_OIDC_TOKEN})"
            echo "    Token preview (first 50 chars): ''${FLY_OIDC_TOKEN:0:50}..."
          else
            echo "    Failed to read token from file, will try API endpoint"
            FLY_OIDC_TOKEN=""
          fi
        fi

        # If token file read failed or doesn't exist, fall back to API call
        if [ -z "$FLY_OIDC_TOKEN" ]; then
          # Wait for Fly API socket
          echo "==> Waiting for Fly API socket..."
          for tries in $(seq 1 ${toString socketWaitSecs}); do
            if [ -S /.fly/api ]; then
              echo "    Fly API socket found after $tries seconds"
              break
            fi
            sleep 1
          done
          if [ ! -S /.fly/api ]; then
            echo "ERROR: Fly API socket /.fly/api never appeared" >&2
            exit 1
          fi

          while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
            echo "==> Attempt $ATTEMPT of $MAX_ATTEMPTS: Fetching OIDC token from Fly.io API..."

            # Capture both stdout and stderr, and the exit code
            set +e
            RESPONSE=$(curl -s --unix-socket /.fly/api -X POST "http://localhost/v1/tokens/oidc" \
              -H 'Content-Type: application/json' \
              -d '{ "aud": "sts.amazonaws.com", "aws_principal_tags": true }' 2>&1)
            CURL_EXIT_CODE=$?
            set -e

            echo "    Curl exit code: $CURL_EXIT_CODE"
            echo "    Response length: ''${#RESPONSE}"

            if [ $CURL_EXIT_CODE -eq 0 ] && [ -n "$RESPONSE" ]; then
              # Extract token from JSON response
              FLY_OIDC_TOKEN=$(echo "$RESPONSE" | jq -r '.token // empty' || true)
              if [ -n "$FLY_OIDC_TOKEN" ]; then
                echo "==> Successfully retrieved OIDC token from API (length: ''${#FLY_OIDC_TOKEN})"
                # Write token to file for AWS SDK
                umask 077
                printf '%s' "$FLY_OIDC_TOKEN" > "${tokenFile}"
                export AWS_WEB_IDENTITY_TOKEN_FILE="${tokenFile}"
                break
              fi
            fi

            if [ $ATTEMPT -lt $MAX_ATTEMPTS ]; then
              echo "    Failed to retrieve token. Sleeping ${toString retryDelaySecs} seconds before retry..."
              sleep ${toString retryDelaySecs}
            fi

            ATTEMPT=$((ATTEMPT + 1))
          done
        fi

        if [ -z "$FLY_OIDC_TOKEN" ]; then
          echo "ERROR: Failed to retrieve OIDC token after $MAX_ATTEMPTS attempts" >&2
          exit 1
        fi

        ${debugBlock}

        echo "==> Assuming AWS role with web identity..."
        if ! CREDENTIALS=$(aws sts assume-role-with-web-identity \
          --role-arn "''${AWS_ROLE_ARN}" \
          --role-session-name "${sessionPrefix}-flyio-$(date +%s)" \
          --web-identity-token "$FLY_OIDC_TOKEN" \
          --duration-seconds ${toString durationSeconds} \
          --output json 2>&1); then
          echo "ERROR: Failed to assume AWS role" >&2
          echo "AWS Error: $CREDENTIALS" >&2
          exit 1
        fi

        # Export AWS credentials for this session
        export AWS_ACCESS_KEY_ID=$(echo "''${CREDENTIALS}" | jq -r '.Credentials.AccessKeyId')
        export AWS_SECRET_ACCESS_KEY=$(echo "''${CREDENTIALS}" | jq -r '.Credentials.SecretAccessKey')
        export AWS_SESSION_TOKEN=$(echo "''${CREDENTIALS}" | jq -r '.Credentials.SessionToken')

        echo "==> AWS credentials configured successfully"

        ${postAuthHook}

        echo "==> Starting application..."
        ${execCommand}
      '';
    };

  # ===========================================================================
  # mkEnvConfig - Helper to generate environment variables for fly.toml/container
  # ===========================================================================
  mkEnvConfig =
    {
      roleArn,
      tokenFile ? "/tmp/fly-oidc-token",
      awsRegion ? "us-west-2",
    }:
    {
      AWS_REGION = awsRegion;
      AWS_WEB_IDENTITY_TOKEN_FILE = tokenFile;
      AWS_ROLE_ARN = roleArn;
    };
}
