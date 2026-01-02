# ==============================================================================
# options.nix
#
# Pure option definitions for the secrets module.
# Contains no implementation logic - only NixOS module option declarations.
#
# Options defined:
# - stackpanel.secrets.enable: Toggle secrets utilities
# - stackpanel.secrets.input-directory: Location of SOPS-encrypted files
# - stackpanel.secrets.environments: Environment-specific configurations
# - stackpanel.secrets.codegen: Code generation settings (TypeScript/Go)
# - stackpanel.secrets.packages: Output packages (internal)
#
# This module is compatible with any Nix module system:
# devenv, NixOS, or standalone lib.evalModules.
# ==============================================================================
{ lib, ... }:
{
  options.stackpanel.secrets = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable StackPanel secrets utilities.";
    };

    input-directory = lib.mkOption {
      type = lib.types.str;
      default = ".stackpanel/secrets";
      description = "Directory where your secrets are stored - should contain a SOPS-encrypted file per environment.";
    };

    environments = lib.mkOption {
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
              description = "List of SOPS-encrypted source files for this environment (without .yaml extension).";
            };
          };
        }
      );
      default = { };
      description = "Environment-specific secrets configurations.";
    };

    codegen = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Name of the generated code package.";
            };
            directory = lib.mkOption {
              type = lib.types.str;
              description = "Output directory for generated code.";
            };
            language = lib.mkOption {
              type = lib.types.enum [
                "typescript"
                "go"
              ];
              description = "Programming language for generated code.";
            };
          };
        }
      );
      default = { };
      description = "Code generation settings for secrets.";
    };

    # Output: packages built by the module (for standalone users)
    packages = lib.mkOption {
      type = lib.types.attrsOf lib.types.package;
      default = { };
      description = "Generated script packages (for standalone/flake users).";
      internal = true;
    };
  };
}
