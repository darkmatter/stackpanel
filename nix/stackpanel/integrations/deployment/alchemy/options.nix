# ==============================================================================
# deployment/alchemy/options.nix
#
# Nix options for centralized Alchemy IaC configuration.
#
# Defines:
#   - stackpanel.deployment.alchemy.enable
#   - stackpanel.deployment.alchemy.version (npm version constraint)
#   - stackpanel.deployment.alchemy.state-store (provider, cloudflare, filesystem config)
#   - stackpanel.deployment.alchemy.app-name (default alchemy app name)
#   - stackpanel.deployment.alchemy.stage (default stage)
#   - stackpanel.deployment.alchemy.package (generated @gen/alchemy config)
#   - stackpanel.deployment.alchemy.secrets (ALCHEMY_STATE_TOKEN + CLOUDFLARE_API_TOKEN management)
#   - stackpanel.deployment.alchemy.helpers (which helpers to include in generated package)
#   - stackpanel.deployment.alchemy.deploy (setup scripts, token provisioning, deploy wrapper)
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
  options.stackpanel.deployment.alchemy = {
    # ==========================================================================
    # Core
    # ==========================================================================
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable the hosted-deployment Alchemy module (generates @gen/alchemy shared package)";
      example = true;
    };

    version = lib.mkOption {
      type = lib.types.str;
      default = "^0.81.2";
      description = ''
        Alchemy npm version constraint.
        Used in the generated package.json and catalog.
        Other modules should reference this instead of hardcoding a version.
      '';
      example = "^0.81.2";
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
        example = "cloudflare";
      };

      cloudflare = {
        api-token-env-var = lib.mkOption {
          type = lib.types.str;
          default = "CLOUDFLARE_API_TOKEN";
          description = "Environment variable name for the Cloudflare API token";
          example = "CLOUDFLARE_API_TOKEN";
        };
      };

      filesystem = {
        directory = lib.mkOption {
          type = lib.types.str;
          default = ".alchemy";
          description = "Local directory for filesystem state store (relative to project root)";
          example = ".alchemy";
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
      example = "my-project";
    };

    stage = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Default deployment stage. When null, stage is determined at runtime
        from the STAGE environment variable.
      '';
      example = "staging";
    };

    # ==========================================================================
    # Generated Package
    # ==========================================================================
    package = {
      name = lib.mkOption {
        type = lib.types.str;
        default = "@gen/alchemy";
        description = "NPM package name for the generated alchemy shared library";
        example = "@gen/alchemy";
      };

      output-dir = lib.mkOption {
        type = lib.types.str;
        default = "packages/gen/alchemy";
        description = "Directory for the generated alchemy package (relative to project root)";
        example = "packages/gen/alchemy";
      };

      extra-dependencies = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = ''
          Additional npm dependencies to include in the generated package.json
          beyond what is automatically determined.
        '';
        example = { "@aws-sdk/client-ssm" = "^3.0.0"; };
      };

      extra-exports = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = { };
        description = ''
          Additional package.json exports beyond the defaults.
          Merged with the auto-generated exports.
        '';
        example = { "./extras" = "./src/extras.ts"; };
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
        example = "ALCHEMY_STATE_TOKEN";
      };

      state-token-sops-path = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          SOPS reference path for the state token.
          Example: "ref+sops://.stack/secrets/vars/common.sops.yaml#/alchemy-state-token"
          When set, the token is automatically injected into the devshell environment.
        '';
        example = "ref+sops://.stack/secrets/vars/common.sops.yaml#/alchemy-state-token";
      };

      cloudflare-token-env-var = lib.mkOption {
        type = lib.types.str;
        default = "CLOUDFLARE_API_TOKEN";
        description = "Environment variable name for the Cloudflare API token";
        example = "CLOUDFLARE_API_TOKEN";
      };

      cloudflare-token-sops-path = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          SOPS reference path for the Cloudflare API token.
          Example: "ref+sops://.stack/secrets/vars/common.sops.yaml#/cloudflare-api-token"
          When set, the token is automatically injected into the devshell environment.
        '';
        example = "ref+sops://.stack/secrets/vars/common.sops.yaml#/cloudflare-api-token";
      };

      sops-group = lib.mkOption {
        type = lib.types.str;
        default = "common";
        description = ''
          SOPS group to store alchemy tokens in.
          Files in `vars/common.sops.yaml` use the shared recipient set. Use a
          specific group (e.g. "dev") when you want a separate SOPS file.
        '';
        example = "common";
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
        example = true;
      };

      bindings = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Include resolveBindings() helper for env var resolution with secret wrapping";
        example = true;
      };

      compute-port = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Include computeProjectPort() helper (mirrors Nix mkProjectPort)";
        example = true;
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
          Enable deploy scripts (alchemy:setup, alchemy:deploy).

          When enabled, registers:
            - alchemy:setup: Interactive Cloudflare authentication and token provisioning
            - alchemy:deploy: Provider-scoped deploy helper that auto-runs setup if needed

          The setup flow uses alchemy's OAuth to authenticate, creates a
          properly-scoped API token via `alchemy util create-cloudflare-token`,
          generates an ALCHEMY_STATE_TOKEN, stores both in the secrets module,
          and bootstraps the CloudflareStateStore worker.
        '';
        example = true;
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
        example = true;
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
        example = "profile";
      };

      run-file = lib.mkOption {
        type = lib.types.str;
        default = "alchemy.run.ts";
        description = ''
          Path to the main alchemy.run.ts file (relative to project root).
          Used by the deploy wrapper to invoke alchemy deploy.
        '';
        example = "alchemy.run.ts";
      };
    };
  };
}
