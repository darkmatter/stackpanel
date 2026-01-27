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
  projectName = config.stackpanel.name or "my-project";

  # ============================================================================
  # Submodule: output declaration (used in module registry)
  # ============================================================================
  outputDeclType = lib.types.submodule {
    options = {
      description = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Human-readable description of this output";
      };

      sensitive = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether this output contains sensitive data";
      };

      sync = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether to sync this output to the storage backend";
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
      };

      description = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Description of what this module provisions";
      };

      path = lib.mkOption {
        type = lib.types.path;
        description = ''
          Path to the TypeScript module file.
          Must default-export a Record<string, string> of outputs.
          Use `import Infra from "@stackpanel/infra"` for the library.
        '';
      };

      inputs = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = { };
        description = ''
          Configuration values passed to the module at runtime.
          Serialized to JSON in .stackpanel/state/infra-inputs.json.
          Values matching ENC[age,...] are decrypted at runtime.
        '';
      };

      dependencies = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "NPM dependencies this module requires in package.json";
      };

      outputs = lib.mkOption {
        type = lib.types.attrsOf outputDeclType;
        default = { };
        description = ''
          Output declarations for this module.
          Keys must match the keys of the default export from the TypeScript file.
          Only outputs with sync=true are written to the storage backend.
        '';
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
    };

    framework = lib.mkOption {
      type = lib.types.enum [ "alchemy" ];
      default = "alchemy";
      description = "IaC framework to use for infrastructure provisioning";
    };

    output-dir = lib.mkOption {
      type = lib.types.str;
      default = "packages/infra";
      description = "Directory for generated infrastructure files (relative to project root)";
    };

    key-format = lib.mkOption {
      type = lib.types.str;
      default = "$module-$key";
      description = ''
        Template for output storage keys.
        Variables: $module (module ID), $key (output key name).
        Example: "$module-$key" -> "aws-secrets-roleArn"
      '';
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
      };

      chamber = {
        service = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = ''
            Chamber service name for output storage.
            Outputs are written as: chamber write <service> <key> -- <value>
          '';
        };
      };

      sops = {
        file-path = lib.mkOption {
          type = lib.types.str;
          default = ".stackpanel/secrets/infra.yaml";
          description = "Path to SOPS-encrypted YAML file for infra outputs";
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
    };

    # ==========================================================================
    # Generated package configuration
    # ==========================================================================
    package = {
      name = lib.mkOption {
        type = lib.types.str;
        default = "@${projectName}/infra";
        description = "NPM package name for the generated infrastructure package";
      };

      dependencies = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Additional package.json dependencies beyond what modules declare";
      };
    };

    # ==========================================================================
    # Outputs stub (cross-resource references)
    # ==========================================================================
    outputs = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.str);
      default = { };
      description = ''
        Infrastructure outputs from the last deployment.
        Keyed by module ID, then by output key.

        Populated by running `infra:pull-outputs` after deployment,
        which reads from the storage backend and writes to
        .stackpanel/data/infra-outputs.nix.

        Example usage in other Nix modules:
          config.stackpanel.infra.outputs.aws-secrets.roleArn
          config.stackpanel.infra.outputs.fly.web-server-ipv4
      '';
    };
  };

  # ============================================================================
  # Config: auto-load outputs from data file
  # ============================================================================
  config = lib.mkIf cfg.enable {
    stackpanel.infra.outputs =
      let
        root = config.stackpanel.root or ./.;
        outputsFile = root + "/.stackpanel/data/infra-outputs.nix";
      in
      lib.mkDefault (
        lib.optionalAttrs (builtins.pathExists outputsFile) (import outputsFile)
      );
  };
}
