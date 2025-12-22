# Secrets module option definitions
{lib}: {
  mkSecretsOptions = {
    globalConfig,
    usersConfig,
    discoverApps,
  }: {
    enable = lib.mkEnableOption "SOPS/vals secrets management";

    backend = lib.mkOption {
      type = lib.types.enum ["vals" "sops"];
      default = globalConfig.backend or "vals";
      description = ''
        Backend for secret resolution.
        - "vals" (recommended): Multi-backend secret resolver supporting SOPS, AWS Secrets Manager, 1Password, Vault, Doppler
        - "sops": Direct SOPS usage only
        vals is backwards-compatible with SOPS files via ref+sops:// URIs
      '';
    };

    users = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          pubkey = lib.mkOption {
            type = lib.types.str;
            description = "AGE public key (age1...) or SSH public key";
          };
          github = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "GitHub username (for display/lookup)";
          };
          admin = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Admin users can decrypt all secrets";
          };
        };
      });
      default = usersConfig;
      example = lib.literalExpression ''
        {
          alice = { pubkey = "age1..."; github = "alice"; admin = true; };
          bob = { pubkey = "age1..."; github = "bobdev"; };
        }
      '';
      description = "Team members and their AGE public keys";
    };

    apps = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          appConfig = lib.mkOption {
            type = lib.types.attrs;
            default = {};
            description = "App-specific configuration (codegen settings)";
          };
          commonSchema = lib.mkOption {
            type = lib.types.attrs;
            default = {};
            description = "Schema shared across all environments";
          };
          environments = lib.mkOption {
            type = lib.types.attrsOf (lib.types.submodule {
              options = {
                schema = lib.mkOption {
                  type = lib.types.attrs;
                  default = {};
                  description = "Environment-specific schema (overrides common)";
                };
                users = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [];
                  description = "User names who can access this environment's secrets";
                };
                extraKeys = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [];
                  description = "Additional AGE keys (CI systems, servers)";
                };
              };
            });
            default = {};
            description = "Per-environment configurations";
          };
        };
      });
      default = discoverApps;
      description = "Per-app secrets configuration (auto-discovered from .stackpanel/secrets/apps/)";
    };

    secretsDir = lib.mkOption {
      type = lib.types.str;
      default = globalConfig.secretsDir or "secrets";
      description = "Directory for encrypted secrets files";
    };

    generatePlaceholders = lib.mkOption {
      type = lib.types.bool;
      default = globalConfig.generatePlaceholders or true;
      description = "Generate placeholder .yaml files for each app/environment";
    };

    defaultEnvironments = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = globalConfig.defaultEnvironments or ["dev" "staging" "prod"];
      description = "Default environments for all apps";
    };
  };
}
