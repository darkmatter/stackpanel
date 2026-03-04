# ==============================================================================
# alchemy/options.nix
#
# Nix options for centralized Alchemy IaC configuration.
#
# Defines:
#   - stackpanel.alchemy.enable
#   - stackpanel.alchemy.version (npm version constraint)
#   - stackpanel.alchemy.state-store (provider, cloudflare, filesystem config)
#   - stackpanel.alchemy.app-name (default alchemy app name)
#   - stackpanel.alchemy.stage (default stage)
#   - stackpanel.alchemy.package (generated @gen/alchemy config)
#   - stackpanel.alchemy.secrets (ALCHEMY_STATE_TOKEN + CLOUDFLARE_API_TOKEN management)
#   - stackpanel.alchemy.helpers (which helpers to include in generated package)
#   - stackpanel.alchemy.deploy (setup scripts, token provisioning, deploy wrapper)
# ==============================================================================
{
  lib,
  config,
  ...
}:
let
  projectName = config.stackpanel.name or "my-project";
in
{
  options.stackpanel.alchemy = {
    # ==========================================================================
    # Core
    # ==========================================================================
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable the Alchemy IaC module (generates @gen/alchemy shared package)";
    };

    version = lib.mkOption {
      type = lib.types.str;
      default = "^0.81.2";
      description = ''
        Alchemy npm version constraint.
        Used in the generated package.json and catalog.
        Other modules should reference this instead of hardcoding a version.
      '';
    };

    # ==========================================================================
    # State Store
    # ==========================================================================
    state-store = {
      provider = lib.mkOption {
        type = lib.types.enum [
          "cloudflare"
          "filesystem"
          "auto"
        ];
        default = "auto";
        description = ''
          State store provider for alchemy.

          - cloudflare: Use CloudflareStateStore (requires API token). Best for
            CI/shared environments where multiple developers need consistent state.
          - filesystem: Use alchemy's default FileSystemStateStore. State is local
            to the machine in the .alchemy directory.
          - auto: Use Cloudflare if CLOUDFLARE_API_TOKEN is present, otherwise
            fall back to filesystem. This is the recommended default.
        '';
      };

      cloudflare = {
        api-token-env-var = lib.mkOption {
          type = lib.types.str;
          default = "CLOUDFLARE_API_TOKEN";
          description = "Environment variable name for the Cloudflare API token";
        };
      };

      filesystem = {
        directory = lib.mkOption {
          type = lib.types.str;
          default = ".alchemy";
          description = "Local directory for filesystem state store (relative to project root)";
        };
      };
    };

    # ==========================================================================
    # App Defaults
    # ==========================================================================
    app-name = lib.mkOption {
      type = lib.types.str;
      default = projectName;
      description = ''
        Default alchemy app name passed to alchemy() constructor.
        Individual consumers can override this.
      '';
    };

    stage = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Default deployment stage. When null, stage is determined at runtime
        from the STAGE environment variable.
      '';
    };

    # ==========================================================================
    # Generated Package
    # ==========================================================================
    package = {
      name = lib.mkOption {
        type = lib.types.str;
        default = "@gen/alchemy";
        description = "NPM package name for the generated alchemy shared library";
      };

      output-dir = lib.mkOption {
        type = lib.types.str;
        default = "packages/gen/alchemy";
        description = "Directory for the generated alchemy package (relative to project root)";
      };

      extra-dependencies = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = ''
          Additional npm dependencies to include in the generated package.json
          beyond what is automatically determined.
        '';
      };

      extra-exports = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = { };
        description = ''
          Additional package.json exports beyond the defaults.
          Merged with the auto-generated exports.
        '';
      };
    };

    # ==========================================================================
    # Secrets
    # ==========================================================================
    secrets = {
      state-token-env-var = lib.mkOption {
        type = lib.types.str;
        default = "ALCHEMY_STATE_TOKEN";
        description = "Environment variable name for the alchemy state store token";
      };

      state-token-sops-path = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          SOPS reference path for the state token.
          Example: "ref+sops://.stack/secrets/vars/common.sops.yaml#/alchemy-state-token"
          When set, the token is automatically injected into the devshell environment.
        '';
      };

      cloudflare-token-env-var = lib.mkOption {
        type = lib.types.str;
        default = "CLOUDFLARE_API_TOKEN";
        description = "Environment variable name for the Cloudflare API token";
      };

      cloudflare-token-sops-path = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          SOPS reference path for the Cloudflare API token.
          Example: "ref+sops://.stack/secrets/vars/common.sops.yaml#/cloudflare-api-token"
          When set, the token is automatically injected into the devshell environment.
        '';
      };

      sops-group = lib.mkOption {
        type = lib.types.str;
        default = "common";
        description = ''
          SOPS group to store alchemy tokens in.
          "common" is encrypted to all group keys, so any team member with
          access to any group can decrypt. Use a specific group (e.g. "dev")
          to restrict access.
        '';
      };
    };

    # ==========================================================================
    # Helpers - control which helpers are included in the generated package
    # ==========================================================================
    helpers = {
      ssm = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Include getSSMSecret() helper for reading AWS SSM parameters";
      };

      bindings = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Include resolveBindings() helper for env var resolution with secret wrapping";
      };

      compute-port = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Include computeProjectPort() helper (mirrors Nix mkProjectPort)";
      };
    };

    # ==========================================================================
    # Deploy - setup scripts, token provisioning, deploy wrapper
    # ==========================================================================
    deploy = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Enable deploy scripts (alchemy:setup, deploy).

          When enabled, registers:
            - alchemy:setup: Interactive Cloudflare authentication and token provisioning
            - deploy: Smart deploy wrapper that auto-runs setup if needed

          The setup flow uses alchemy's OAuth to authenticate, creates a
          properly-scoped API token via `alchemy util create-cloudflare-token`,
          generates an ALCHEMY_STATE_TOKEN, stores both in the secrets module,
          and bootstraps the CloudflareStateStore worker.
        '';
      };

      auto-provision-state-store = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Automatically provision the CloudflareStateStore worker during setup.

          After creating tokens, runs a bootstrap alchemy deploy that uses
          filesystem state to deploy the alchemy-state-service Cloudflare Worker.
          This solves the chicken-and-egg problem: subsequent deploys can use
          CloudflareStateStore because the worker already exists.
        '';
      };

      token-scopes = lib.mkOption {
        type = lib.types.enum [
          "profile"
          "god"
        ];
        default = "profile";
        description = ''
          How to scope the generated Cloudflare API token.

          - profile: Create a token mirroring the OAuth scopes from the alchemy
            profile. This is the principle of least privilege.
          - god: Create a token with full write access to everything. Simpler
            but overly permissive. Use only for personal projects.
        '';
      };

      run-file = lib.mkOption {
        type = lib.types.str;
        default = "alchemy.run.ts";
        description = ''
          Path to the main alchemy.run.ts file (relative to project root).
          Used by the deploy wrapper to invoke alchemy deploy.
        '';
      };
    };
  };
}
