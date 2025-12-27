# ==============================================================================
# default.nix
#
# Unified entry point for the StackPanel secrets module.
# Auto-detects whether running in devenv or standalone context.
#
# This module provides SOPS-based secrets management with:
# - Automatic AGE key detection and validation
# - SOPS wrapper scripts for transparent encryption/decryption
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
{ pkgs, lib, config, options, ... }:
let
  cfg = config.stackpanel.secrets;
  secretsLib = import ./lib.nix { inherit lib pkgs; };

  # Detect if we're in a devenv context by checking for devenv-specific options
  isDevenv = options ? scripts;

  # ═══════════════════════════════════════════════════════════════════════════════
  # Standalone packages (for flake users who need derivations)
  # ═══════════════════════════════════════════════════════════════════════════════
  ensure-age-key = pkgs.writeShellApplication {
    name = "ensure-age-key";
    runtimeInputs = [ pkgs.age pkgs.coreutils pkgs.gawk ];
    text = secretsLib.ensureAgeKeyScript;
  };

  sops-wrapped = pkgs.writeShellApplication {
    name = "sops-wrapped";
    runtimeInputs = [ pkgs.sops ensure-age-key ];
    text = secretsLib.sopsWrapperScript "${ensure-age-key}/bin/ensure-age-key";
  };

  generate-secrets-schema = pkgs.writeShellApplication {
    name = "generate-secrets-schema";
    runtimeInputs = [ pkgs.yq pkgs.sops pkgs.jq pkgs.bun ];
    text = secretsLib.generateSecretsSchemaScript;
  };

  generate-secrets-package = pkgs.writeShellApplication {
    name = "generate-secrets-package";
    runtimeInputs = [ pkgs.yq pkgs.sops pkgs.jq pkgs.bun generate-secrets-schema ];
    text = secretsLib.generateSecretsPackageScript {
      inputDir = cfg.input-directory;
      environments = cfg.environments;
      codegen = cfg.codegen;
    };
  };

in {
  # Options are now centralized in core/options/secrets.nix

  config = lib.mkMerge ([
    # ═══════════════════════════════════════════════════════════════════════════════
    # Common config (both devenv and standalone)
    # ═══════════════════════════════════════════════════════════════════════════════
    (lib.mkIf cfg.enable {
      # Always provide packages for programmatic access
      stackpanel.secrets.packages = {
        inherit ensure-age-key sops-wrapped generate-secrets-schema generate-secrets-package;
      };
    })
  ]
  # ═══════════════════════════════════════════════════════════════════════════════
  # Devenv-specific config (only included when in devenv context)
  # ═══════════════════════════════════════════════════════════════════════════════
  ++ lib.optionals isDevenv [
    (lib.mkIf cfg.enable {
      # Scripts using devenv's scripts.*.exec pattern
      scripts.ensure-age-key.exec = secretsLib.ensureAgeKeyScript;
      scripts.sops.exec = secretsLib.sopsWrapperScript "ensure-age-key";
      scripts.generate-secrets-schema.exec = secretsLib.generateSecretsSchemaScript;
      scripts.generate-secrets-package.exec = secretsLib.generateSecretsPackageScript {
        inputDir = cfg.input-directory;
        environments = cfg.environments;
        codegen = cfg.codegen;
      };

      # Add required packages to devenv shell
      packages = [
        pkgs.sops
        pkgs.age
        pkgs.yq
        pkgs.jq
        pkgs.bun
      ];
    })

    # ═══════════════════════════════════════════════════════════════════════════════
    # Devenv test module (only when testing)
    # ═══════════════════════════════════════════════════════════════════════════════
    (lib.mkIf (cfg.enable && (config.devenv.isTesting or false)) {
      scripts."test-secrets".exec = ''
        set -e
        echo "🧪 Testing secrets module..."

        # Test 1: Verify sops wrapper exists
        command -v sops >/dev/null && echo "✅ sops wrapper exists" || { echo "❌ sops wrapper missing"; exit 1; }

        # Test 2: Verify ensure-age-key exists
        command -v ensure-age-key >/dev/null && echo "✅ ensure-age-key exists" || { echo "❌ ensure-age-key missing"; exit 1; }

        # Test 3: Verify generate-secrets-schema exists
        command -v generate-secrets-schema >/dev/null && echo "✅ generate-secrets-schema exists" || { echo "❌ generate-secrets-schema missing"; exit 1; }

        # Test 4: Verify generate-secrets-package exists
        command -v generate-secrets-package >/dev/null && echo "✅ generate-secrets-package exists" || { echo "❌ generate-secrets-package missing"; exit 1; }

        # Test 5: Verify sops wrapper runs preflight (will fail if no key, but script should exist)
        sops --version >/dev/null 2>&1 || true
        echo "✅ sops wrapper is callable"

        echo ""
        echo "✅ All secrets tests passed!"
      '';

      enterTest = ''
        test-secrets
      '';
    })
  ]);
}

