# ==============================================================================
# secrets.nix
#
# Secrets management options - SOPS-encrypted secrets with codegen.
#
# This module imports options from the proto schema (db/schemas/secrets.proto.nix)
# and extends them with Nix-specific runtime options like packages.
#
# The proto schema is the SINGLE SOURCE OF TRUTH for the data structure.
#
# Environments are derived from stackpanel.apps.<app>.environments automatically.
# Manual secrets.environments still works and takes precedence.
# ==============================================================================
{ lib, config, ... }:
let
  # Import the db module to get proto-derived options
  db = import ../../db { inherit lib; };

  # Default AGE key file locations to check (in order)
  defaultAgeKeyFiles = [
    "\${SOPS_AGE_KEY_FILE:-}"
    "\${HOME}/.config/sops/age/keys.txt"
    "\${HOME}/.age/keys.txt"
    "\${HOME}/.config/age/keys.txt"
    "/etc/sops/age/keys.txt"
  ];

  # Compute environments from apps.<app>.environments
  # Format: "<app>/<env>" -> { name, sources, public-keys }
  computedEnvsFromApps = lib.concatMapAttrs (
    appName: appCfg:
    lib.mapAttrs' (
      envName: envCfg:
      lib.nameValuePair "${appName}/${envName}" {
        name = envCfg.name or envName;
        sources = envCfg.sources or [ ];
        public-keys = envCfg.public-keys or [ ];
      }
    ) (appCfg.environments or { })
  ) (config.stackpanel.apps or { });

  # Merge computed with manual (manual takes precedence)
  mergedEnvironments = computedEnvsFromApps // (config.stackpanel.secrets.environments or { });
in
{
  # Secrets options derived from proto schema
  # The proto defines: enable, input_directory, environments, codegen
  # These are converted to kebab-case: input-directory
  options.stackpanel.secrets = db.extend.secrets // {
    # Auto-generate a local AGE key if none exists
    auto-generate-key = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Automatically generate a local AGE key on first shell entry if none exists.
        
        This ensures there's always at least one decryption method available,
        which is required for encrypting secrets. The generated key is stored in
        .stackpanel/state/age-key.txt (gitignored) and is local to your machine.
        
        For team-wide secrets, configure shared keys via the UI or .sops.yaml.
      '';
    };

    # AGE key file locations to check for decryption
    age-key-files = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = defaultAgeKeyFiles;
      description = ''
        Paths to AGE key files to check for decryption.
        Checked in order; the first existing file wins.
        Supports shell variables like $HOME and $SOPS_AGE_KEY_FILE.

        Default locations:
        - $SOPS_AGE_KEY_FILE (if set)
        - ~/.config/sops/age/keys.txt (SOPS default)
        - ~/.age/keys.txt (age default)
        - ~/.config/age/keys.txt (XDG-style)
        - /etc/sops/age/keys.txt (system-wide)
      '';
      example = [
        "\${HOME}/.config/sops/age/keys.txt"
        "/run/secrets/age-key"
      ];
    };

    # Single AGE identity file for decryption (used by generate-sops-secrets)
    age-identity-file = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = ''
        Path to AGE or SSH private key for decrypting .age secrets.
        
        Supported key types:
        - AGE keys: ~/.config/age/key.txt, ~/.age/key.txt
        - SSH keys: ~/.ssh/id_ed25519, ~/.ssh/id_rsa
        
        If empty, the script will search default AGE key locations.
        SSH keys require explicit path specification.
      '';
      example = "~/.ssh/id_ed25519";
    };

    # AWS KMS configuration for SOPS encryption
    kms = lib.mkOption {
      type = lib.types.submodule {
        options = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Enable AWS KMS encryption in SOPS.";
          };
          key-arn = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "AWS KMS key ARN for encrypting/decrypting secrets.";
            example = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012";
          };
          aws-profile = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "AWS profile to use for KMS operations. Leave empty to use default credentials.";
          };
        };
      };
      default = { };
      description = ''
        AWS KMS configuration for SOPS encryption.
        When enabled, KMS keys will be added to .sops.yaml creation rules.
        Works with AWS Roles Anywhere if stackpanel.aws.roles-anywhere is enabled.
      '';
    };

    # Computed environments (read-only) - derived from apps.<app>.environments + manual
    environmentsComputed = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Name of the environment.";
            };
            public-keys = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "List of AGE public keys that can decrypt this environment.";
            };
            sources = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "List of SOPS-encrypted source files for this environment.";
            };
          };
        }
      );
      readOnly = true;
      description = ''
        Computed environments derived from stackpanel.apps.<app>.environments.
        
        Format: "<app>/<env>" -> { name, sources, public-keys }
        
        This merges:
        1. Environments defined in apps.<app>.environments (auto-computed)
        2. Manual environments in secrets.environments (takes precedence)
      '';
    };

    # Nix-specific extension: generated packages (not in data schema)
    packages = lib.mkOption {
      type = lib.types.attrsOf lib.types.package;
      default = { };
      description = "Generated script packages (for standalone/flake users).";
      internal = true;
    };
  };

  # Set computed environments value
  config.stackpanel.secrets.environmentsComputed = lib.mkDefault mergedEnvironments;
}
