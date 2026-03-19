{
  lib,
  mkEnvVar,
  categories,
}:
rec {
  # Core Stackpanel Variables
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
      default = ".stack";
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
      description = "Path to the source Nix config file (.stack/config.nix)";
      category = categories.core;
      source = "nix";
      example = "/home/user/my-project/.stack/config.nix";
      goField = "NixConfigPath";
    };

    STACKPANEL_CONFIG_JSON = mkEnvVar {
      name = "STACKPANEL_CONFIG_JSON";
      description = "Path to the Nix-generated config JSON in the Nix store (for Go CLI)";
      category = categories.core;
      source = "nix";
      example = "/nix/store/xxx-stackpanel-config.json";
      goField = "ConfigJsonPath";
    };
  };

  # Paths & Directories
  paths = {
    STACKPANEL_STATE_DIR = mkEnvVar {
      name = "STACKPANEL_STATE_DIR";
      description = "Directory for runtime state (credentials, caches, etc.)";
      category = categories.paths;
      source = "nix";
      required = true;
      example = "/home/user/my-project/.stack/state";
      goField = "StateDir";
    };

    STACKPANEL_STATE_FILE = mkEnvVar {
      name = "STACKPANEL_STATE_FILE";
      description = "Full path to the stackpanel.json state file";
      category = categories.paths;
      source = "nix";
      example = "/home/user/my-project/.stack/state/stackpanel.json";
      goField = "StateFile";
    };

    STACKPANEL_SHELL_LOG = mkEnvVar {
      name = "STACKPANEL_SHELL_LOG";
      description = "Log file capturing shell entry output";
      category = categories.paths;
      source = "nix";
      example = "/home/user/my-project/.stack/state/shell.log";
      goField = "ShellLog";
    };

    STACKPANEL_GEN_DIR = mkEnvVar {
      name = "STACKPANEL_GEN_DIR";
      description = "Directory for generated files (configs, scripts)";
      category = categories.paths;
      source = "nix";
      example = "/home/user/my-project/.stack/gen";
      goField = "GenDir";
    };

    STACKPANEL_DATA_DIR = mkEnvVar {
      name = "STACKPANEL_DATA_DIR";
      description = "Directory for persistent data (databases, etc.)";
      category = categories.paths;
      source = "nix";
      example = "/home/user/my-project/.stack/data";
      goField = "DataDir";
    };
  };

  # Stackpanel Agent Variables
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

    STACKPANEL_USER_CONFIG = mkEnvVar {
      name = "STACKPANEL_USER_CONFIG";
      description = "Path to user-level config file (stores cross-repo data like projects list)";
      category = categories.agent;
      source = "dynamic";
      default = "~/.config/stackpanel/stackpanel.yaml";
      example = "/home/user/.config/stackpanel/stackpanel.yaml";
      goField = "UserConfigPath";
    };
  };

  # Step CA (Certificate Authority)
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

  # AWS & Roles Anywhere
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

  # MinIO (S3-Compatible Storage)
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

  # Services Config
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

  # Devenv Integration
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

  # IDE Integration
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

}
