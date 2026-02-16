# ==============================================================================
# alchemy/options.nix
#
# Nix options for centralized Alchemy IaC configuration.
#
# Defines:
#   - stackpanel.alchemy.enable
#   - stackpanel.alchemy.version (npm version constraint)
#   - stackpanel.alchemy.stateStore (provider, cloudflare, filesystem config)
#   - stackpanel.alchemy.appName (default alchemy app name)
#   - stackpanel.alchemy.stage (default stage)
#   - stackpanel.alchemy.package (generated @gen/alchemy config)
#   - stackpanel.alchemy.secrets (ALCHEMY_STATE_TOKEN management)
#   - stackpanel.alchemy.helpers (which helpers to include in generated package)
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
    stateStore = {
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
        apiTokenEnvVar = lib.mkOption {
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
    appName = lib.mkOption {
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
      stateTokenEnvVar = lib.mkOption {
        type = lib.types.str;
        default = "ALCHEMY_STATE_TOKEN";
        description = "Environment variable name for the alchemy state store token";
      };

      stateTokenSopsPath = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          SOPS reference path for the state token.
          Example: "ref+sops://.stackpanel/secrets/groups/dev.yaml#/ALCHEMY_STATE_TOKEN"
          When set, the token is automatically injected into the devshell environment.
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

      computePort = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Include computeProjectPort() helper (mirrors Nix mkProjectPort)";
      };
    };
  };
}
