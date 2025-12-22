# SOPS/vals secrets management - Per-app secrets with inheritance
# Standalone module - no flake-parts dependency
#
# Architecture:
#   .stackpanel/secrets/
#   ├── config.yaml          # Global settings (backend, secretsDir)
#   ├── users.yaml           # Team members and AGE keys
#   └── apps/
#       └── {appName}/
#           ├── config.yaml  # App codegen settings (language, output path)
#           ├── common.yaml  # Shared schema across all environments
#           ├── dev.yaml     # Dev-specific schema + access control
#           ├── staging.yaml # Staging-specific schema + access control
#           └── prod.yaml    # Production-specific schema + access control
#
# Philosophy: Use standard SOPS workflow, enhanced with vals for multi-backend
#   - sops secrets/api/dev.yaml           # edit app secrets
#   - vals eval -f secrets.template.yaml  # resolve from any backend
#   - git add secrets/*.yaml              # encrypted files safe to commit
#
{
  lib,
  config,
  pkgs,
  ...
}: let
  cfg = config.stackpanel.secrets;

  # Path to .stackpanel/secrets directory
  secretsConfigDir = "${config.env.DEVENV_ROOT}/.stackpanel/secrets";

  # Import library functions
  secretsLib = import ./lib.nix {inherit lib pkgs secretsConfigDir;};

  # Import options factory
  optionsLib = import ./options.nix {inherit lib;};

  # Import file generation functions
  filesLib = import ./files.nix {inherit lib;};

  # Import schema generation (pass genDir for output path)
  schemasLib = import ./schemas.nix {
    inherit lib;
    genDir = config.stackpanel.genDir;
  };

  # Load configs from YAML files
  globalConfig = secretsLib.loadGlobalConfig;
  usersConfig = secretsLib.loadUsersConfig;

  # Generate .sops.yaml rules
  sopsYamlContent = secretsLib.generateSopsRules {
    apps = cfg.apps;
    users = cfg.users;
    isAgeKey = secretsLib.isAgeKey;
  };

  # Generate JSON schemas
  schemas = schemasLib.generateSchemas;
in {
  options.stackpanel.secrets = optionsLib.mkSecretsOptions {
    inherit globalConfig usersConfig;
    discoverApps = secretsLib.discoverApps;
  };

  config = lib.mkIf cfg.enable {
    # Add packages based on backend
    # vals includes sops support via ref+sops:// so we always include sops and age
    packages = [
      pkgs.sops
      pkgs.age
    ] ++ lib.optional (cfg.backend == "vals") pkgs.vals;

    # Generate all files (including JSON schemas)
    files =
      filesLib.generateFiles {
        inherit cfg sopsYamlContent;
        toYaml = secretsLib.toYaml;
        secretsPlaceholder = filesLib.secretsPlaceholder;
        secretsGitignore = filesLib.secretsGitignore;
        secretsReadme = filesLib.secretsReadme;
      }
      // schemasLib.generateSchemaFiles schemas;
  };
}

