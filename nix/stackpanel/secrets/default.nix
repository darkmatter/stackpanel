# ==============================================================================
# default.nix
#
# Unified entry point for the StackPanel secrets module.
# Auto-detects whether running in devenv or standalone context.
#
# This module provides secrets management with:
# - Automatic AGE key detection and validation
# - SOPS wrapper scripts for transparent encryption/decryption
# - Agenix/agenix-rekey integration for per-secret encryption
# - Code generation for type-safe secrets access (TypeScript/Go)
# - Environment-specific secrets merging
#
# Usage:
#   Devenv users:
#     imports = [ ./modules/secrets ];
#     stackpanel.secrets.enable = true;
#
#   Standalone/flake users:
#     imports = [ ./modules/secrets ];
#     _module.args.pkgs = nixpkgs.legacyPackages.x86_64-linux;
#     stackpanel.secrets.enable = true;
#     # Access packages via: config.stackpanel.secrets.packages
# ==============================================================================
{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.stackpanel.secrets;
  
  # AWS config for KMS integration
  awsCfg = config.stackpanel.aws.roles-anywhere or { enable = false; };
  sstCfg = config.stackpanel.sst or { enable = false; kms = { enable = false; }; };
  
  # Auto-compute KMS ARN from SST outputs if available
  # Format: arn:aws:kms:REGION:ACCOUNT_ID:alias/ALIAS
  computedKmsArn = 
    if sstCfg.kms.enable or false && awsCfg.account-id or "" != "" then
      "arn:aws:kms:${awsCfg.region or "us-west-2"}:${awsCfg.account-id}:alias/${sstCfg.kms.alias or "${config.stackpanel.name or "stackpanel"}-secrets"}"
    else
      cfg.kms.key-arn or "";
  
  # Check if KMS should be enabled (explicit config OR AWS is enabled with SST KMS)
  kmsEnabled = cfg.kms.enable or false || (awsCfg.enable or false && sstCfg.kms.enable or false);
  kmsArn = if cfg.kms.key-arn or "" != "" then cfg.kms.key-arn else computedKmsArn;
  
  secretsLib = import ./lib.nix {
    inherit lib pkgs;
    ageKeyFiles = cfg.age-key-files;
  };

  # Pure Nix TypeScript codegen - generates files via stackpanel.files
  envTypescript = import ../lib/codegen/env-typescript.nix { inherit lib config; };

  # ═══════════════════════════════════════════════════════════════════════════════
  # Standalone packages (for flake users who need derivations)
  # ═══════════════════════════════════════════════════════════════════════════════
  ensure-age-key = pkgs.writeShellApplication {
    name = "ensure-age-key";
    runtimeInputs = [
      pkgs.age
      pkgs.coreutils
      pkgs.gawk
    ];
    text = secretsLib.ensureAgeKeyScript;
  };

  sops-wrapped = pkgs.writeShellApplication {
    name = "sops-wrapped";
    runtimeInputs = [
      pkgs.sops
      ensure-age-key
    ];
    text = secretsLib.sopsWrapperScript "${ensure-age-key}/bin/ensure-age-key";
  };

  generate-secrets-schema = pkgs.writeShellApplication {
    name = "generate-secrets-schema";
    runtimeInputs = [
      pkgs.yq-go
      pkgs.sops
      pkgs.jq
      pkgs.bun
    ];
    text = secretsLib.generateSecretsSchemaScript;
  };

  generate-secrets-package = pkgs.writeShellApplication {
    name = "generate-secrets-package";
    runtimeInputs = [
      pkgs.yq-go
      pkgs.sops
      pkgs.jq
      pkgs.bun
      generate-secrets-schema
    ];
    text = secretsLib.generateSecretsPackageScript {
      inputDir = cfg.input-directory;
      environments = cfg.environmentsComputed;
      codegen = cfg.codegen;
    };
  };

  generate-sops-secrets = pkgs.writeShellApplication {
    name = "generate-sops-secrets";
    runtimeInputs = [
      pkgs.nix
      pkgs.age
      pkgs.yq-go
      pkgs.sops
      pkgs.jq
    ];
    text = secretsLib.generateSopsSecretsScript {
      secretsDir = ".stackpanel/secrets";
      dataDir = ".stackpanel/data";
      ageIdentityFile = cfg.age-identity-file;
    };
  };

  generate-sops-config = pkgs.writeShellApplication {
    name = "generate-sops-config";
    runtimeInputs = [
      pkgs.nix
      pkgs.age
      pkgs.jq
      pkgs.ssh-to-age
    ];
    text = secretsLib.generateSopsConfigScript {
      secretsDir = ".stackpanel/secrets";
      dataDir = ".stackpanel/data";
      kmsConfig = cfg.kms;
    };
  };
in
{
  # Import the agenix integration module, combined secrets module, and wrapped packages module
  imports = [
    ./agenix.nix
    ./combined.nix
    ./wrapped.nix
  ];

  # Options are now centralized in core/options/secrets.nix

  config = lib.mkMerge [
    # ═══════════════════════════════════════════════════════════════════════════════
    # Auto-enable SST KMS when secrets.kms is enabled and AWS is configured
    # ═══════════════════════════════════════════════════════════════════════════════
    (lib.mkIf (cfg.enable && cfg.kms.enable or false && awsCfg.enable or false) {
      # Enable SST to provision KMS resources
      stackpanel.sst = {
        enable = lib.mkDefault true;
        kms.enable = lib.mkDefault true;
      };
    })

    # ═══════════════════════════════════════════════════════════════════════════════
    # Common config (both devenv and standalone)
    # ═══════════════════════════════════════════════════════════════════════════════
    (lib.mkIf cfg.enable {
      # Always provide packages for programmatic access
      stackpanel.secrets.packages = {
        inherit
          ensure-age-key
          sops-wrapped
          generate-secrets-schema
          generate-secrets-package
          generate-sops-secrets
          generate-sops-config
          ;
      };

      # ═══════════════════════════════════════════════════════════════════════════
      # Pure Nix TypeScript codegen - generates znv modules via stackpanel.files
      # No shell scripts needed - files are generated on shell entry automatically
      # ═══════════════════════════════════════════════════════════════════════════
      stackpanel.files.entries = lib.mkIf envTypescript.enabled envTypescript.fileEntries;

      # Add required packages to devshell
      stackpanel.devshell.packages = [
        pkgs.sops
        pkgs.age
        pkgs.yq
        pkgs.jq
        pkgs.bun
        pkgs.nix  # For generate-sops-secrets (nix eval)
      ];

      # Auto-generate AGE key on shell entry if none exists
      # This ensures there's always at least one decryption method available
      # NOTE: Wrapped in subshell () so that 'exit' statements don't terminate the entire shellHook
      stackpanel.devshell.hooks.before = lib.mkIf cfg.auto-generate-key [
        ''
          (
          ${secretsLib.autoGenerateAgeKeyScript}
          )
        ''
      ];

      # Scripts for secrets management
      stackpanel.scripts = {
        ensure-age-key = {
          exec = secretsLib.ensureAgeKeyScript;
          description = "Ensure an AGE key exists";
        };
        auto-generate-age-key = {
          exec = secretsLib.autoGenerateAgeKeyScript;
          description = "Auto-generate an AGE key if missing";
        };
        sops = {
          exec = secretsLib.sopsWrapperScript "ensure-age-key";
          description = "SOPS wrapper with AGE key management";
        };
        generate-secrets-schema = {
          exec = secretsLib.generateSecretsSchemaScript;
          description = "Generate JSON schema for secrets";
        };
        generate-secrets-package = {
          exec = secretsLib.generateSecretsPackageScript {
            inputDir = cfg.input-directory;
            environments = cfg.environmentsComputed;
            codegen = cfg.codegen;
          };
          description = "Generate secrets package code";
        };
        generate-sops-secrets = {
          exec = secretsLib.generateSopsSecretsScript {
            secretsDir = ".stackpanel/secrets";
            dataDir = ".stackpanel/data";
            ageIdentityFile = cfg.age-identity-file;
          };
          description = "Generate SOPS secrets files";
        };
        generate-sops-config = {
          exec = secretsLib.generateSopsConfigScript {
            secretsDir = ".stackpanel/secrets";
            dataDir = ".stackpanel/data";
            kmsConfig = cfg.kms;
          };
          description = "Generate SOPS configuration";
        };
        # User-friendly aliases for on-demand generation
        "secrets:generate" = {
          exec = ''
            echo "🔐 Regenerating SOPS secrets..."
            echo "📁 Step 1/2: Generating SOPS config (.sops.yaml)..."
            ${generate-sops-config}/bin/generate-sops-config
            echo "🔒 Step 2/2: Generating encrypted YAML files..."
            ${generate-sops-secrets}/bin/generate-sops-secrets
            echo ""
            echo "✅ Secrets regenerated successfully"
            echo ""
            echo "💡 TypeScript types are generated via stackpanel.files on shell entry"
            echo "   Run 'write-files' manually if you need to update them"
          '';
          description = "Regenerate SOPS-encrypted YAML files from app variables";
        };

        # =====================================================================
        # Master Key Management (Envelope Encryption)
        # =====================================================================
        "secrets:init-master" = {
          exec = secretsLib.initMasterKeyScript {
            inherit kmsEnabled kmsArn;
            kmsProfile = cfg.kms.aws-profile or "";
          };
          description = "Initialize master key for envelope encryption${lib.optionalString kmsEnabled " (with KMS)"}";
        };
        "secrets:add-user" = {
          exec = secretsLib.addUserToMasterKeyScript;
          description = "Add a user to master key recipients";
        };
        "secrets:remove-user" = {
          exec = secretsLib.removeUserFromMasterKeyScript;
          description = "Remove a user from master key recipients";
        };
        "secrets:migrate-to-master" = {
          exec = secretsLib.migrateToMasterKeyScript;
          description = "Migrate existing .age files to use master key";
        };
      };
    })
  ];
}
