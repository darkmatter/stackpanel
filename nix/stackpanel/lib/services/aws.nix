# ==============================================================================
# services/aws.nix
#
# AWS IAM Roles Anywhere authentication utilities using X.509 certificates.
# Pure functions that work with any Nix module system.
#
# Creates self-contained credential helper scripts with certificates embedded
# in the Nix store. The resulting scripts have NO external file dependencies
# and can be used in OCI images, copied to other machines, etc.
#
# == USAGE ==
#
#   let awsLib = import ./aws.nix { inherit pkgs lib; };
#
#   # For certificates known at build time (embedded in Nix store):
#   awsLib.mkAwsCredentialProcess {
#     cert = builtins.readFile ./my-cert.pem;  # or path to file
#     key = builtins.readFile ./my-key.pem;
#     accountId = "123456789012";
#     roleName = "MyRole";
#     trustAnchorArn = "arn:aws:rolesanywhere:...";
#     profileArn = "arn:aws:rolesanywhere:...";
#   }
#
#   # For certificates at runtime paths (Step CA, etc.):
#   awsLib.mkRuntimeAwsScripts {
#     certPath = "$STACKPANEL_STATE_DIR/step/device.crt";  # Runtime path
#     keyPath = "$STACKPANEL_STATE_DIR/step/device.key";
#     accountId = "123456789012";
#     roleName = "MyRole";
#     trustAnchorArn = "arn:aws:rolesanywhere:...";
#     profileArn = "arn:aws:rolesanywhere:...";
#   }
#
# == EXPORTS ==
#
#   - mkAwsCredentialProcess: Creates a self-contained credential-process script
#   - mkAwsCredScripts: Creates a full suite of AWS credential helpers
#   - mkRuntimeAwsScripts: Scripts that use runtime certificate paths
#
# ==============================================================================
{
  pkgs,
  lib ? pkgs.lib,
}: let
  # Helper to normalize cert/key input to a store path
  # Accepts: PEM string, path to file, or derivation
  toStorePath = name: input:
    if builtins.isString input && lib.hasPrefix "-----BEGIN" input
    then pkgs.writeText name input
    else input;

in {
  # ===========================================================================
  # mkAwsCredentialProcess - Create a self-contained credential-process script
  # ===========================================================================
  mkAwsCredentialProcess = {
    # Certificate content (PEM string) or path to file
    cert,
    # Private key content (PEM string) or path to file
    key,
    # Optional intermediate certificates
    intermediates ? null,
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
    # Optional role session name
    roleSessionName ? null,
    # Enable debug logging
    debug ? false,
  }: let
    certFile = toStorePath "aws-cert.pem" cert;
    keyFile = toStorePath "aws-key.pem" key;
    intermediatesFile = if intermediates != null
      then toStorePath "aws-intermediates.pem" intermediates
      else null;
    roleArn = "arn:aws:iam::${accountId}:role/${roleName}";
  in pkgs.writeShellScriptBin "aws-credential-process" ''
    set -euo pipefail
    exec ${pkgs.aws-signing-helper}/bin/aws_signing_helper credential-process \
      --certificate "${certFile}" \
      --private-key "${keyFile}" \
      ${lib.optionalString (intermediatesFile != null) ''--intermediates "${intermediatesFile}" \''} \
      --role-arn "${roleArn}" \
      --trust-anchor-arn "${trustAnchorArn}" \
      --profile-arn "${profileArn}" \
      --region "${region}" \
      ${lib.optionalString (roleSessionName != null) ''--role-session-name "${roleSessionName}"''} \
      ${lib.optionalString debug "--debug"}
  '';

  # ===========================================================================
  # mkAwsCredScripts - Create a full suite of AWS credential helpers
  # ===========================================================================
  mkAwsCredScripts = {
    # Certificate content (PEM string) or path to file
    cert,
    # Private key content (PEM string) or path to file
    key,
    # Optional intermediate certificates
    intermediates ? null,
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
    # Optional role session name
    roleSessionName ? null,
    # Enable debug logging
    debug ? false,
  }: let
    certFile = toStorePath "aws-cert.pem" cert;
    keyFile = toStorePath "aws-key.pem" key;
    intermediatesFile = if intermediates != null
      then toStorePath "aws-intermediates.pem" intermediates
      else null;
    roleArn = "arn:aws:iam::${accountId}:role/${roleName}";

    # Debug logging helper
    logDebug = msg: lib.optionalString debug ''
      echo "[rolesanywhere]: ${msg}" >&2
    '';

    # =========================================================================
    # Credential Process - the core script called by AWS SDKs
    # =========================================================================
    credentialProcess = pkgs.writeShellScriptBin "aws-credential-process" ''
      set -euo pipefail
      exec ${pkgs.aws-signing-helper}/bin/aws_signing_helper credential-process \
        --certificate "${certFile}" \
        --private-key "${keyFile}" \
        ${lib.optionalString (intermediatesFile != null) ''--intermediates "${intermediatesFile}" \''} \
        --role-arn "${roleArn}" \
        --trust-anchor-arn "${trustAnchorArn}" \
        --profile-arn "${profileArn}" \
        --region "${region}" \
        ${lib.optionalString (roleSessionName != null) ''--role-session-name "${roleSessionName}"''} \
        ${lib.optionalString debug "--debug"}
    '';

    # =========================================================================
    # AWS Config File - a store path that can be used directly
    # This is the foundation - all other tools reference this config.
    # =========================================================================
    awsConfigFile = pkgs.writeText "aws-config" ''
[default]
region = ${region}
credential_process = ${credentialProcess}/bin/aws-credential-process
'';

    # =========================================================================
    # AWS Creds Env - exports environment for AWS SDK to use credential_process
    # This doesn't fetch credentials directly - it sets up the config file
    # so the SDK can call credential_process on demand.
    # =========================================================================
    awsCredsEnv = pkgs.writeShellScriptBin "aws-creds-env" ''
      set -euo pipefail
      ${logDebug "aws-creds-env starting"}
      ${logDebug "using config file: ${awsConfigFile}"}

      # Export config-based auth - SDK will call credential_process automatically
      echo "export AWS_CONFIG_FILE=${awsConfigFile}"
      echo "export AWS_SHARED_CREDENTIALS_FILE=/dev/null"
      echo "export AWS_REGION=${region}"
    '';

    # =========================================================================
    # Wrapped AWS CLI (uses config file, SDK handles credential_process)
    # =========================================================================
    awsCli = pkgs.writeShellScriptBin "aws" ''
      export AWS_CONFIG_FILE="${awsConfigFile}"
      export AWS_SHARED_CREDENTIALS_FILE="/dev/null"
      export AWS_REGION="${region}"
      exec ${pkgs.awscli2}/bin/aws "$@"
    '';

    # =========================================================================
    # Generate AWS config file for SDK use (writes content to a file at runtime)
    # For most use cases, prefer awsConfigFile which is already a store path.
    # =========================================================================
    generateAwsConfig = pkgs.writeShellScriptBin "aws-generate-config" ''
      set -euo pipefail

      OUTPUT="''${1:-/dev/stdout}"

      cat > "$OUTPUT" << 'EOF'
[default]
region = ${region}
credential_process = ${credentialProcess}/bin/aws-credential-process
EOF

      if [[ "$OUTPUT" != "/dev/stdout" ]]; then
        chmod 600 "$OUTPUT"
      fi
    '';

    # =========================================================================
    # Run any command with AWS credentials (uses config file, no eval needed)
    # =========================================================================
    withAws = pkgs.writeShellScriptBin "with-aws" ''
      export AWS_CONFIG_FILE="${awsConfigFile}"
      export AWS_SHARED_CREDENTIALS_FILE="/dev/null"
      export AWS_REGION="${region}"
      exec "$@"
    '';

  in {
    inherit
      credentialProcess
      awsConfigFile
      awsCredsEnv
      awsCli
      generateAwsConfig
      withAws
      ;

    # All packages for easy inclusion in devenv.packages
    allPackages = [
      credentialProcess
      awsCredsEnv
      awsCli
      generateAwsConfig
      withAws
      pkgs.aws-signing-helper
    ];

    # Required dependencies
    requiredPackages = [
      pkgs.aws-signing-helper
    ];

    # Environment variables for AWS SDK configuration
    env = {
      AWS_REGION = region;
      AWS_SHARED_CREDENTIALS_FILE = "/dev/null";
    };

    # Store paths for OCI image building
    storePaths = {
      cert = certFile;
      key = keyFile;
      intermediates = intermediatesFile;
    };

    # =========================================================================
    # Wrap a package so all its binaries have AWS credentials
    #
    # This creates a fully self-contained wrapper where:
    # - AWS_CONFIG_FILE points to a store path
    # - The config uses credential_process which is also a store path
    # - The credential_process references cert/key which are store paths
    # - No runtime file generation needed
    # =========================================================================
    wrapPackage = pkg: pkgs.symlinkJoin {
      name = "${pkg.name or pkg.pname or "wrapped"}-with-aws";
      paths = [ pkg ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        for bin in $out/bin/*; do
          if [ -f "$bin" ] && [ -x "$bin" ]; then
            wrapProgram "$bin" \
              --set AWS_CONFIG_FILE "${awsConfigFile}" \
              --set AWS_SHARED_CREDENTIALS_FILE "/dev/null" \
              --set AWS_REGION "${region}"
          fi
        done
      '';
    };
  };

  # ===========================================================================
  # mkRuntimeAwsScripts - Scripts that use runtime certificate paths
  #
  # Use this when certificates are generated at runtime (e.g., Step CA)
  # and aren't available during Nix evaluation.
  #
  # The credential_process script is a store path, but it reads cert/key
  # from runtime paths (environment variables).
  # ===========================================================================
  mkRuntimeAwsScripts = {
    # Runtime path to certificate (shell variable like $CERT_PATH or literal path)
    certPath ? "$AWS_CERT_PATH",
    # Runtime path to private key
    keyPath ? "$AWS_KEY_PATH",
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
    # Optional role session name
    roleSessionName ? null,
    # Enable debug logging
    debug ? false,
  }: let
    roleArn = "arn:aws:iam::${accountId}:role/${roleName}";

    # Debug logging helper
    logDebug = msg: lib.optionalString debug ''
      echo "[rolesanywhere]: ${msg}" >&2
    '';

    # =========================================================================
    # Credential Process - uses runtime paths from environment
    # This is a store path, but reads cert/key from env vars at runtime.
    # =========================================================================
    credentialProcess = pkgs.writeShellScriptBin "aws-credential-process" ''
      set -euo pipefail

      _cert="''${AWS_CERT_PATH:-${certPath}}"
      _key="''${AWS_KEY_PATH:-${keyPath}}"

      ${logDebug "credential-process: using cert=$_cert key=$_key"}

      if [[ ! -f "$_cert" ]]; then
        echo "Error: Certificate not found at $_cert" >&2
        echo "Hint: Run 'ensure-device-cert' to create it" >&2
        exit 1
      fi

      if [[ ! -f "$_key" ]]; then
        echo "Error: Private key not found at $_key" >&2
        exit 1
      fi

      exec ${pkgs.aws-signing-helper}/bin/aws_signing_helper credential-process \
        --certificate "$_cert" \
        --private-key "$_key" \
        --role-arn "${roleArn}" \
        --trust-anchor-arn "${trustAnchorArn}" \
        --profile-arn "${profileArn}" \
        --region "${region}" \
        ${lib.optionalString (roleSessionName != null) ''--role-session-name "${roleSessionName}"''} \
        ${lib.optionalString debug "--debug"}
    '';

    # =========================================================================
    # AWS Config File - a store path referencing the credential_process
    # The credential_process will read cert/key from env vars at runtime.
    # =========================================================================
    awsConfigFile = pkgs.writeText "aws-config" ''
[default]
region = ${region}
credential_process = ${credentialProcess}/bin/aws-credential-process
'';

    # =========================================================================
    # Generate AWS config file for SDK use (writes to a file at runtime)
    # For most use cases, prefer awsConfigFile which is already a store path.
    # =========================================================================
    generateAwsConfig = pkgs.writeShellScriptBin "aws-generate-config" ''
      set -euo pipefail

      OUTPUT="''${1:-/dev/stdout}"

      cat > "$OUTPUT" << EOF
[default]
region = ${region}
credential_process = ${credentialProcess}/bin/aws-credential-process
EOF

      if [[ "$OUTPUT" != "/dev/stdout" ]]; then
        chmod 600 "$OUTPUT"
      fi
    '';

    # =========================================================================
    # AWS Creds Env - exports environment for AWS SDK to use credential_process
    # =========================================================================
    awsCredsEnv = pkgs.writeShellScriptBin "aws-creds-env" ''
      set -euo pipefail
      ${logDebug "aws-creds-env starting"}
      ${logDebug "using config file: ${awsConfigFile}"}

      echo "export AWS_CONFIG_FILE=${awsConfigFile}"
      echo "export AWS_SHARED_CREDENTIALS_FILE=/dev/null"
      echo "export AWS_REGION=${region}"
    '';

    # =========================================================================
    # Wrapped AWS CLI (uses config file, SDK handles credential_process)
    # =========================================================================
    awsCli = pkgs.writeShellScriptBin "aws" ''
      export AWS_CONFIG_FILE="${awsConfigFile}"
      export AWS_SHARED_CREDENTIALS_FILE="/dev/null"
      export AWS_REGION="${region}"
      exec ${pkgs.awscli2}/bin/aws "$@"
    '';

    # =========================================================================
    # Run any command with AWS credentials
    # =========================================================================
    withAws = pkgs.writeShellScriptBin "with-aws" ''
      export AWS_CONFIG_FILE="${awsConfigFile}"
      export AWS_SHARED_CREDENTIALS_FILE="/dev/null"
      export AWS_REGION="${region}"
      exec "$@"
    '';

    # =========================================================================
    # Wrap a package so all its binaries have AWS credentials
    #
    # For runtime certs, this sets AWS_CONFIG_FILE to the store-path config.
    # The credential_process in that config reads cert paths from env vars.
    # =========================================================================
    wrapPackage = pkg: pkgs.symlinkJoin {
      name = "${pkg.name or pkg.pname or "wrapped"}-with-aws";
      paths = [ pkg ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        for bin in $out/bin/*; do
          if [ -f "$bin" ] && [ -x "$bin" ]; then
            wrapProgram "$bin" \
              --set AWS_CONFIG_FILE "${awsConfigFile}" \
              --set AWS_SHARED_CREDENTIALS_FILE "/dev/null" \
              --set AWS_REGION "${region}"
          fi
        done
      '';
    };

  in {
    inherit
      credentialProcess
      awsConfigFile
      awsCredsEnv
      awsCli
      generateAwsConfig
      withAws
      wrapPackage
      ;

    # All packages for easy inclusion in devenv.packages
    allPackages = [
      credentialProcess
      awsCredsEnv
      awsCli
      generateAwsConfig
      withAws
      pkgs.aws-signing-helper
      pkgs.chamber
    ];

    # Required dependencies
    requiredPackages = [
      pkgs.aws-signing-helper
      pkgs.chamber
    ];

    # Environment variables for AWS SDK configuration
    env = {
      AWS_REGION = region;
      AWS_SHARED_CREDENTIALS_FILE = "/dev/null";
      AWS_CONFIG_FILE = "${awsConfigFile}";  # Coerce derivation to store path string
    };
  };
}
