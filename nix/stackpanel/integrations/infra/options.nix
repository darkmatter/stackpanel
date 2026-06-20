# ==============================================================================
# infra/options.nix
#
# Core options for the infrastructure module system.
#
# Defines:
#   - stackpanel.infra.enable, framework, output-dir, key-format
#   - stackpanel.infra.storage-backend (chamber, sops, ssm, none)
#   - stackpanel.infra.modules (internal registry)
#   - stackpanel.infra.package (generated package.json config)
#   - stackpanel.infra.outputs (stub for cross-resource references)
# ==============================================================================
{
  lib,
  config,
  ...
}:
let
  cfg = config.stackpanel.infra;

  # ============================================================================
  # Alchemy peer dependency mapping
  #
  # Maps alchemy resource imports to their required npm peer dependencies.
  # Used for validation to ensure all required dependencies are declared.
  # ============================================================================

  # ============================================================================
  # Submodule: output declaration (used in module registry)
  # ============================================================================
  outputDeclType = lib.types.submodule {
    options = {
      description = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Human-readable description of this output";
        example = "IAM role ARN used by deploy jobs";
      };

      sensitive = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether this output contains sensitive data";
        example = true;
      };

      sync = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether to sync this output to the storage backend";
        example = true;
      };
    };
  };

  # ============================================================================
  # Submodule: infra module registry entry
  # ============================================================================
  infraModuleType = lib.types.submodule {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        description = "Human-readable name of this infra module";
        example = "AWS Secrets";
      };

      description = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Description of what this module provisions";
        example = "KMS key and IAM role for encrypted secrets";
      };

      path = lib.mkOption {
        type = lib.types.path;
        description = ''
          Path to the TypeScript module file.
          Must default-export a Record<string, string> of outputs.
          Use `import Infra from "@stackpanel/infra"` for the library.
        '';
        example = lib.literalExpression "./modules/aws-secrets/index.ts";
      };

      inputs = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = { };
        description = ''
          Configuration values passed to the module at runtime.
          Serialized to JSON in .stack/state/infra-inputs.json.
          Values matching ENC[age,...] are decrypted at runtime.
        '';
        example = {
          region = "us-west-2";
          roleName = "stackpanel-secrets-role";
        };
      };

      dependencies = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = ''
          NPM dependencies this module requires.
          Merged into the infra package.json dependencies.

          For external flake modules, prefer providing bunDeps instead
          for pre-validated, reproducible dependencies.
        '';
        example = { "alchemy" = "^0.81.2"; };
      };

      bunDeps = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = null;
        description = ''
          Pre-fetched Bun dependency cache from bun2nix.fetchBunDeps.

          External flakes should provide this for reproducible builds.
          When provided, these deps are validated at Nix eval time and
          merged with other modules' deps.

          Example (in a flake providing an infra module):
            bunDeps = bun2nix.fetchBunDeps {
              bunNix = ./bun.nix;
            };

          The flake should also ship package.json, bun.lock, and bun.nix
          alongside the module.
        '';
        example = null;
      };

      outputs = lib.mkOption {
        type = lib.types.attrsOf outputDeclType;
        default = { };
        description = ''
          Output declarations for this module.
          Keys must match the keys of the default export from the TypeScript file.
          Only outputs with sync=true are written to the storage backend.
        '';
        example = {
          roleArn = {
            description = "IAM role ARN";
            sync = true;
          };
        };
      };
    };
  };

in
{
  # ============================================================================
  # Options
  # ============================================================================
  options.stackpanel.infra = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable the infrastructure module system";
      example = true;
    };

    framework = lib.mkOption {
      type = lib.types.enum [ "alchemy" ];
      default = "alchemy";
      description = ''
        IaC framework to use for infrastructure provisioning.
        Currently only "alchemy" is supported. The deployment Alchemy module at
        config.stackpanel.deployment.alchemy provides the shared SDK configuration
        (version, state store, helpers) that this module consumes.
      '';
      example = "alchemy";
    };

    output-dir = lib.mkOption {
      type = lib.types.str;
      default = "packages/gen/infra";
      description = "Directory for generated infrastructure files (relative to project root)";
      example = "packages/gen/infra";
    };

    key-format = lib.mkOption {
      type = lib.types.str;
      default = "$module-$key";
      description = ''
        Template for output storage keys.
        Variables: $module (module ID), $key (output key name).
        Example: "$module-$key" -> "aws-secrets-roleArn"
      '';
      example = "$module-$key";
    };

    # ==========================================================================
    # Storage backend for persisting outputs
    # ==========================================================================
    storage-backend = {
      type = lib.mkOption {
        type = lib.types.enum [
          "chamber"
          "sops"
          "ssm"
          "none"
        ];
        default = "none";
        description = "Storage backend for persisting infrastructure outputs";
        example = "sops";
      };

      chamber = {
        service = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = ''
            Chamber service name for output storage.
            Outputs are written as: chamber write <service> <key> -- <value>
          '';
          example = "stackpanel-infra";
        };
      };

      sops = {
        file-path = lib.mkOption {
          type = lib.types.str;
          default = ".stack/secrets/infra/dev.sops.yaml";
          description = ''
            Path to SOPS-encrypted YAML file for infra outputs.
            Defaults to a dedicated infra file. Uses `sops set` for non-destructive
            per-key updates, preserving existing secrets in the file.
          '';
          example = ".stack/secrets/infra/prod.sops.yaml";
        };

        group = lib.mkOption {
          type = lib.types.str;
          default = "dev";
          description = ''
            Secrets group to write outputs to (e.g., "dev", "prod", "common").
            Used to resolve the SOPS file path from the secrets directory:
              <secrets-dir>/vars/<group>.sops.yaml
            When set, overrides file-path.
          '';
          example = "prod";
        };
      };

      ssm = {
        prefix = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = ''
            SSM Parameter Store path prefix for infra outputs.
            Outputs are written to: <prefix>/<formatted-key>
          '';
          example = "/stackpanel/prod/infra";
        };
      };
    };

    # ==========================================================================
    # Module registry (populated by infra modules)
    # ==========================================================================
    modules = lib.mkOption {
      type = lib.types.attrsOf infraModuleType;
      default = { };
      description = ''
        Registry of infrastructure modules.
        Each infra module registers itself here with its path, inputs,
        dependencies, and output declarations.
        Do not set this directly — infra modules populate it via config.
      '';
      example = {
        aws-secrets = {
          name = "AWS Secrets";
          path = ./modules/aws-secrets/index.ts;
          outputs.roleArn.sync = true;
        };
      };
    };

    # ==========================================================================
    # Generated package configuration
    # ==========================================================================
    package = {
      name = lib.mkOption {
        type = lib.types.str;
        default = "@gen/infra";
        description = "NPM package name for the generated infrastructure package";
        example = "@gen/infra";
      };

      dependencies = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Additional package.json dependencies beyond what modules declare";
        example = { "@alchemy/aws" = "^0.81.2"; };
      };

      bun-nix = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = ''
          Path to a bun.nix file for the infra package.

          When provided, dependencies are validated at Nix evaluation time
          via bun2nix.fetchBunDeps, catching invalid versions and missing
          peer dependencies before runtime.

          Bootstrapping workflow:
            1. Enter devshell: nix develop
            2. Generate lock file: cd ${cfg.output-dir} && bun2nix
            3. Set this option: bun-nix = ./${cfg.output-dir}/bun.nix;
            4. Re-enter devshell to enable validation

          See: https://nix-community.github.io/bun2nix/building-packages/fetchBunDeps.html
        '';
        example = lib.literalExpression "./packages/gen/infra/bun.nix";
      };
    };

    # ==========================================================================
    # Outputs stub (cross-resource references)
    # ==========================================================================
    outputs = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
      default = { };
      description = ''
        Infrastructure outputs from the last deployment.
        Keyed by module ID, then by output key.

        Populated by running `infra:pull-outputs` after deployment,
        which reads from the storage backend and writes to
        .stack/data/infra-outputs.nix.

        Outputs are typically strings, but may include structured values
        (e.g., machine inventories) when modules emit complex outputs.

        Machine inventories are expected at:
          config.stackpanel.infra.outputs.machines.machines

        Suggested shape:
          machines = {
            web-1 = {
              host = "web-1.example.com";
              ssh = { user = "root"; port = 22; };
              roles = [ "web" ];
              tags = [ "prod" ];
              arch = "x86_64-linux";
            };
          };

        Example usage in other Nix modules:
          config.stackpanel.infra.outputs.aws-secrets.roleArn
          config.stackpanel.infra.outputs.fly.web-server-ipv4
      '';
      example = {
        aws-secrets = {
          roleArn = "arn:aws:iam::123456789012:role/stackpanel-secrets-role";
        };
      };
    };

  };

  # ============================================================================
  # Config: auto-load outputs from data file
  # ============================================================================
  config = lib.mkIf cfg.enable {
    stackpanel.infra.outputs =
      let
        root = if config.stackpanel.root != null then config.stackpanel.root else ./.;
        outputsFile = root + "/.stack/data/infra-outputs.nix";
      in
      lib.mkDefault (lib.optionalAttrs (builtins.pathExists outputsFile) (import outputsFile));
  };
}
