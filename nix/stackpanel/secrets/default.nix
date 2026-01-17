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
  secretsLib = import ./lib.nix {
    inherit lib pkgs;
    ageKeyFiles = cfg.age-key-files;
  };

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
      pkgs.yq
      pkgs.sops
      pkgs.jq
      pkgs.bun
    ];
    text = secretsLib.generateSecretsSchemaScript;
  };

  generate-secrets-package = pkgs.writeShellApplication {
    name = "generate-secrets-package";
    runtimeInputs = [
      pkgs.yq
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

      # Add required packages to devshell
      stackpanel.devshell.packages = [
        pkgs.sops
        pkgs.age
        pkgs.yq
        pkgs.jq
        pkgs.bun
        pkgs.nix  # For generate-sops-secrets (nix eval)
      ];

      # Commands using stackpanel abstraction
      stackpanel.devshell.commands = {
        ensure-age-key = {
          exec = secretsLib.ensureAgeKeyScript;
        };
        sops = {
          exec = secretsLib.sopsWrapperScript "ensure-age-key";
        };
        generate-secrets-schema = {
          exec = secretsLib.generateSecretsSchemaScript;
        };
        generate-secrets-package = {
          exec = secretsLib.generateSecretsPackageScript {
            inputDir = cfg.input-directory;
            environments = cfg.environmentsComputed;
            codegen = cfg.codegen;
          };
        };
        generate-sops-secrets = {
          exec = secretsLib.generateSopsSecretsScript {
            secretsDir = ".stackpanel/secrets";
            dataDir = ".stackpanel/data";
            ageIdentityFile = cfg.age-identity-file;
          };
        };
        generate-sops-config = {
          exec = secretsLib.generateSopsConfigScript {
            secretsDir = ".stackpanel/secrets";
            dataDir = ".stackpanel/data";
            kmsConfig = cfg.kms;
          };
        };
      };
    })
  ];
}
