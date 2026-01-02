# ==============================================================================
# envvars.nix - Centralized Environment Variable Registry
# ==============================================================================
#
# This file is the single source of truth for all environment variables used
# throughout the Stackpanel ecosystem (Nix modules, Go CLI, shell scripts).
#
# Each variable includes:
#   - name: The environment variable name
#   - description: Human-readable description
#   - category: Grouping for documentation
#   - source: Where the variable is set (nix, shell, dynamic)
#   - required: Whether the variable is required for basic operation
#   - default: Default value if applicable
#   - example: Example value for documentation
#
# Usage in Nix:
#   envvars = import ./envvars.nix { inherit lib; };
#   envvars.core.STACKPANEL_ROOT.name  # => "STACKPANEL_ROOT"
#
# The registry can be used to:
#   1. Generate documentation automatically
#   2. Validate environment at shell startup
#   3. Keep Go CLI in sync with Nix definitions
#   4. Provide autocomplete/IDE hints
#
# ==============================================================================
{
  lib ? import <nixpkgs/lib>,
}:
let
  # Helper to create an env var definition
  mkEnvVar =
    {
      name,
      description,
      category,
      source ? "nix",
      required ? false,
      default ? null,
      example ? null,
      deprecated ? false,
      deprecationMessage ? null,
      goField ? null, # Corresponding Go struct field name
    }:
    {
      inherit
        name
        description
        category
        source
        required
        default
        example
        deprecated
        deprecationMessage
        goField
        ;
    };

  # Categories for organizing variables
  categories = {
    core = "Core Stackpanel";
    paths = "Paths & Directories";
    agent = "Stackpanel Agent";
    stepca = "Step CA (Certificates)";
    aws = "AWS & Roles Anywhere";
    minio = "MinIO (S3-Compatible Storage)";
    services = "Services Config";
    devenv = "Devenv Integration";
    ide = "IDE Integration";
  };
in
rec {
  inherit categories;

  # ===========================================================================
  # Core Stackpanel Variables
  # ===========================================================================
  core = {
    STACKPANEL_ROOT = mkEnvVar {
      name = "STACKPANEL_ROOT";
      description = "Absolute path to the project root directory";
      category = categories.core;
      source = "nix";
      required = true;
      example = "/home/user/my-project";
      goField = "ProjectRoot";
    };

    STACKPANEL_ROOT_MARKER = mkEnvVar {
      name = "STACKPANEL_ROOT_MARKER";
      description = "Filename used as a marker to identify project root";
      category = categories.core;
      source = "nix";
      default = ".stackpanel-root";
      goField = "RootMarker";
    };

    STACKPANEL_ROOT_DIR_NAME = mkEnvVar {
      name = "STACKPANEL_ROOT_DIR_NAME";
      description = "Name of the .stackpanel directory within the project";
      category = categories.core;
      source = "nix";
      default = ".stackpanel";
    };

    STACKPANEL_SHELL_ID = mkEnvVar {
      name = "STACKPANEL_SHELL_ID";
      description = "Unique identifier for the current shell session";
      category = categories.core;
      source = "nix";
      default = "1";
    };

    STACKPANEL_NIX_CONFIG = mkEnvVar {
      name = "STACKPANEL_NIX_CONFIG";
      description = "Path to the Nix-generated config JSON in the Nix store";
      category = categories.core;
      source = "nix";
      example = "/nix/store/xxx-stackpanel-config.json";
      goField = "NixConfigPath";
    };
  };

  # ===========================================================================
  # Paths & Directories
  # ===========================================================================
  paths = {
    STACKPANEL_STATE_DIR = mkEnvVar {
      name = "STACKPANEL_STATE_DIR";
      description = "Directory for runtime state (credentials, caches, etc.)";
      category = categories.paths;
      source = "nix";
      required = true;
      example = "/home/user/my-project/.stackpanel/state";
      goField = "StateDir";
    };

    STACKPANEL_STATE_FILE = mkEnvVar {
      name = "STACKPANEL_STATE_FILE";
      description = "Full path to the stackpanel.json state file";
      category = categories.paths;
      source = "nix";
      example = "/home/user/my-project/.stackpanel/state/stackpanel.json";
      goField = "StateFile";
    };

    STACKPANEL_GEN_DIR = mkEnvVar {
      name = "STACKPANEL_GEN_DIR";
      description = "Directory for generated files (configs, scripts)";
      category = categories.paths;
      source = "nix";
      example = "/home/user/my-project/.stackpanel/gen";
      goField = "GenDir";
    };

    STACKPANEL_DATA_DIR = mkEnvVar {
      name = "STACKPANEL_DATA_DIR";
      description = "Directory for persistent data (databases, etc.)";
      category = categories.paths;
      source = "nix";
      example = "/home/user/my-project/.stackpanel/data";
      goField = "DataDir";
    };
  };

  # ===========================================================================
  # Stackpanel Agent Variables
  # ===========================================================================
  agent = {
    STACKPANEL_PROJECT_ROOT = mkEnvVar {
      name = "STACKPANEL_PROJECT_ROOT";
      description = "Project root override for the agent (when spawned externally)";
      category = categories.agent;
      source = "dynamic";
      goField = "ProjectRoot";
    };

    STACKPANEL_AUTH_TOKEN = mkEnvVar {
      name = "STACKPANEL_AUTH_TOKEN";
      description = "Authentication token for the agent API";
      category = categories.agent;
      source = "dynamic";
      goField = "AuthToken";
    };

    STACKPANEL_API_ENDPOINT = mkEnvVar {
      name = "STACKPANEL_API_ENDPOINT";
      description = "API endpoint URL for the agent";
      category = categories.agent;
      source = "dynamic";
      default = "http://localhost:6401";
      goField = "APIEndpoint";
    };
  };

  # ===========================================================================
  # Step CA (Certificate Authority)
  # ===========================================================================
  stepca = {
    STEP_CA_URL = mkEnvVar {
      name = "STEP_CA_URL";
      description = "URL of the Step CA server";
      category = categories.stepca;
      source = "nix";
      example = "https://ca.internal:443";
    };

    STEP_CA_FINGERPRINT = mkEnvVar {
      name = "STEP_CA_FINGERPRINT";
      description = "SHA256 fingerprint of the Step CA root certificate";
      category = categories.stepca;
      source = "nix";
      example = "3996f98e09f54bdfc705bb0f022d70dc3e15230c009add60508d0593ae805d5a";
    };
  };

  # ===========================================================================
  # AWS & Roles Anywhere
  # ===========================================================================
  aws = {
    AWS_TRUST_ANCHOR_ARN = mkEnvVar {
      name = "AWS_TRUST_ANCHOR_ARN";
      description = "ARN of the IAM Roles Anywhere trust anchor";
      category = categories.aws;
      source = "nix";
      example = "arn:aws:rolesanywhere:us-east-1:123456789012:trust-anchor/abc123";
    };

    AWS_PROFILE_ARN = mkEnvVar {
      name = "AWS_PROFILE_ARN";
      description = "ARN of the IAM Roles Anywhere profile";
      category = categories.aws;
      source = "nix";
      example = "arn:aws:rolesanywhere:us-east-1:123456789012:profile/def456";
    };

    AWS_ROLE_ARN = mkEnvVar {
      name = "AWS_ROLE_ARN";
      description = "ARN of the IAM role to assume via Roles Anywhere";
      category = categories.aws;
      source = "nix";
      example = "arn:aws:iam::123456789012:role/DeveloperRole";
    };

    AWS_REGION = mkEnvVar {
      name = "AWS_REGION";
      description = "Default AWS region for API calls";
      category = categories.aws;
      source = "nix";
      default = "us-east-1";
    };

    AWS_ACCESS_KEY_ID = mkEnvVar {
      name = "AWS_ACCESS_KEY_ID";
      description = "AWS access key ID (set dynamically by credential scripts)";
      category = categories.aws;
      source = "dynamic";
    };

    AWS_SECRET_ACCESS_KEY = mkEnvVar {
      name = "AWS_SECRET_ACCESS_KEY";
      description = "AWS secret access key (set dynamically by credential scripts)";
      category = categories.aws;
      source = "dynamic";
    };

    AWS_SESSION_TOKEN = mkEnvVar {
      name = "AWS_SESSION_TOKEN";
      description = "AWS session token for temporary credentials";
      category = categories.aws;
      source = "dynamic";
    };

    AWS_SHARED_CREDENTIALS_FILE = mkEnvVar {
      name = "AWS_SHARED_CREDENTIALS_FILE";
      description = "Path to AWS credentials file (set to /dev/null to force Roles Anywhere)";
      category = categories.aws;
      source = "nix";
      default = "/dev/null";
    };

    AWS_CERT_PATH = mkEnvVar {
      name = "AWS_CERT_PATH";
      description = "Override path to device certificate for Roles Anywhere";
      category = categories.aws;
      source = "dynamic";
    };

    AWS_KEY_PATH = mkEnvVar {
      name = "AWS_KEY_PATH";
      description = "Override path to device private key for Roles Anywhere";
      category = categories.aws;
      source = "dynamic";
    };

    AWS_SIGNING_HELPER = mkEnvVar {
      name = "AWS_SIGNING_HELPER";
      description = "Override path to aws_signing_helper binary";
      category = categories.aws;
      source = "dynamic";
    };
  };

  # ===========================================================================
  # MinIO (S3-Compatible Storage)
  # ===========================================================================
  minio = {
    MINIO_ROOT_USER = mkEnvVar {
      name = "MINIO_ROOT_USER";
      description = "MinIO admin username";
      category = categories.minio;
      source = "nix";
      default = "minioadmin";
    };

    MINIO_ROOT_PASSWORD = mkEnvVar {
      name = "MINIO_ROOT_PASSWORD";
      description = "MinIO admin password";
      category = categories.minio;
      source = "nix";
      default = "minioadmin";
    };

    MINIO_ENDPOINT = mkEnvVar {
      name = "MINIO_ENDPOINT";
      description = "MinIO S3 endpoint URL";
      category = categories.minio;
      source = "nix";
      example = "http://localhost:9000";
    };

    MINIO_ACCESS_KEY = mkEnvVar {
      name = "MINIO_ACCESS_KEY";
      description = "MinIO access key (alias for MINIO_ROOT_USER)";
      category = categories.minio;
      source = "nix";
    };

    MINIO_SECRET_KEY = mkEnvVar {
      name = "MINIO_SECRET_KEY";
      description = "MinIO secret key (alias for MINIO_ROOT_PASSWORD)";
      category = categories.minio;
      source = "nix";
    };

    MINIO_CONSOLE_ADDRESS = mkEnvVar {
      name = "MINIO_CONSOLE_ADDRESS";
      description = "MinIO console bind address (e.g., :9001)";
      category = categories.minio;
      source = "nix";
    };

    S3_ENDPOINT = mkEnvVar {
      name = "S3_ENDPOINT";
      description = "S3-compatible endpoint URL (points to MinIO when enabled)";
      category = categories.minio;
      source = "nix";
      example = "http://localhost:9000";
    };
  };

  # ===========================================================================
  # Services Config
  # ===========================================================================
  services = {
    STACKPANEL_STABLE_PORT = mkEnvVar {
      name = "STACKPANEL_STABLE_PORT";
      description = "Base port for the project (index 0 in the port layout)";
      category = categories.services;
      source = "nix";
      example = "6400";
    };

    STACKPANEL_SERVICES_CONFIG = mkEnvVar {
      name = "STACKPANEL_SERVICES_CONFIG";
      description = "JSON array of service definitions with ports";
      category = categories.services;
      source = "nix";
      example = ''[{"key":"POSTGRES","name":"PostgreSQL","port":6410}]'';
    };
  };

  # ===========================================================================
  # Devenv Integration
  # ===========================================================================
  devenv = {
    DEVENV_ROOT = mkEnvVar {
      name = "DEVENV_ROOT";
      description = "Root directory of the devenv project (set by devenv)";
      category = categories.devenv;
      source = "devenv";
    };

    DEVENV_STATE = mkEnvVar {
      name = "DEVENV_STATE";
      description = "State directory for devenv (set by devenv)";
      category = categories.devenv;
      source = "devenv";
    };

    DEVENV_DOTFILE = mkEnvVar {
      name = "DEVENV_DOTFILE";
      description = "Path to devenv dotfile directory";
      category = categories.devenv;
      source = "devenv";
    };

    DEVENV_PROFILE = mkEnvVar {
      name = "DEVENV_PROFILE";
      description = "Current devenv profile path";
      category = categories.devenv;
      source = "devenv";
    };
  };

  # ===========================================================================
  # IDE Integration
  # ===========================================================================
  ide = {
    DEVENV_VSCODE_SHELL = mkEnvVar {
      name = "DEVENV_VSCODE_SHELL";
      description = "Marker to prevent shell recursion in VS Code (1 = inside VS Code shell)";
      category = categories.ide;
      source = "nix";
    };

    EDITOR = mkEnvVar {
      name = "EDITOR";
      description = "Default text editor";
      category = categories.ide;
      source = "nix";
      default = "vim";
    };
  };

  # ===========================================================================
  # Helper Functions
  # ===========================================================================

  # Get all variables as a flat list
  allVariables = lib.flatten [
    (lib.attrValues core)
    (lib.attrValues paths)
    (lib.attrValues agent)
    (lib.attrValues stepca)
    (lib.attrValues aws)
    (lib.attrValues minio)
    (lib.attrValues services)
    (lib.attrValues devenv)
    (lib.attrValues ide)
  ];

  # Get all required variables
  requiredVariables = lib.filter (v: v.required) allVariables;

  # Get variables by category
  byCategory = category: lib.filter (v: v.category == category) allVariables;

  # Get variables by source
  bySource = source: lib.filter (v: v.source == source) allVariables;

  # Generate environment validation script
  mkValidationScript =
    {
      pkgs,
      strict ? false,
    }:
    pkgs.writeShellScriptBin "stackpanel-validate-env" ''
      #!/usr/bin/env bash
      set -euo pipefail

      ERRORS=0
      WARNINGS=0

      check_required() {
        local var_name="$1"
        local description="$2"
        if [[ -z "''${!var_name:-}" ]]; then
          echo "❌ MISSING: $var_name - $description"
          ((ERRORS++)) || true
        else
          echo "✓ $var_name"
        fi
      }

      echo "Validating Stackpanel environment variables..."
      echo ""

      ${lib.concatMapStringsSep "\n" (v: ''
        check_required "${v.name}" "${v.description}"
      '') requiredVariables}

      echo ""
      if [[ $ERRORS -gt 0 ]]; then
        echo "Found $ERRORS missing required variables"
        ${if strict then "exit 1" else "exit 0"}
      else
        echo "All required variables are set!"
      fi
    '';

  # Generate markdown documentation
  mkDocumentation =
    let
      renderVar = v: ''
        ### `${v.name}`

        ${v.description}

        | Property | Value |
        |----------|-------|
        | Category | ${v.category} |
        | Source | ${v.source} |
        | Required | ${if v.required then "Yes" else "No"} |
        ${lib.optionalString (v.default != null) "| Default | `${v.default}` |"}
        ${lib.optionalString (v.example != null) "| Example | `${v.example}` |"}
        ${lib.optionalString (v.goField != null) "| Go Field | `${v.goField}` |"}
        ${lib.optionalString v.deprecated "| ⚠️ Deprecated | ${
          v.deprecationMessage or "This variable is deprecated"
        } |"}
      '';

      renderCategory = name: vars: ''
        ## ${name}

        ${lib.concatMapStringsSep "\n---\n" renderVar vars}
      '';
    in
    ''
      # Stackpanel Environment Variables Reference

      This document is auto-generated from `nix/stackpanel/core/lib/envvars.nix`.

      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (name: _: renderCategory name (byCategory name)) categories
      )}
    '';

  # Generate Go constants file content
  mkGoConstants = ''
    // Code generated by envvars.nix. DO NOT EDIT.
    package envvars

    // Environment variable names used by Stackpanel
    const (
    ${lib.concatMapStringsSep "\n" (v: ''
      // ${v.description}
      ${lib.toUpper (lib.replaceStrings [ "-" " " ] [ "_" "_" ] v.name)} = "${v.name}"
    '') (lib.filter (v: v.source != "devenv") allVariables)}
    )

    // Categories groups environment variables by their purpose
    var Categories = map[string][]string{
    ${lib.concatMapStringsSep "\n" (cat: ''
      	"${cat}": {
      ${lib.concatMapStringsSep ",\n" (
        v: ''${lib.toUpper (lib.replaceStrings [ "-" " " ] [ "_" "_" ] v.name)}''
      ) (byCategory cat)}
      	},
    '') (lib.attrValues categories)}
    }
  '';
}
