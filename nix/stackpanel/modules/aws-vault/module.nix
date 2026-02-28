{
  lib,
  config,
  pkgs,
  ...
}:

let
  meta = import ./meta.nix;
  cfg = config.stackpanel.aws-vault;
  sp = config.stackpanel;

  wrapperType =
    { name, defaultPkg }:
    {
      enable = lib.mkEnableOption "Enable ${name} wrapper with aws-vault";
      package = lib.mkOption {
        type = lib.types.package;
        default = defaultPkg;
        description = "The ${name} package to wrap.";
      };
    };

  mkWrapper =
    { name, wrappedPkg }:
    pkgs.writeScriptBin name ''
      #!${pkgs.bash}/bin/bash
      exec ${lib.getExe cfg.package} exec ${cfg.profile} -- ${lib.getExe wrappedPkg} "$@"
    '';
in
{
  # ===========================================================================
  # Options - Configuration goes in a separate namespace
  # ===========================================================================
  options.stackpanel.aws-vault = {
    enable = lib.mkEnableOption meta.description;

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.aws-vault;
      description = "The aws-vault package to use.";
    };

    profile = lib.mkOption {
      type = lib.types.str;
      default = "default";
      description = "The AWS profile to use with aws-vault.";
    };

    awscliWrapper = lib.mkOption {
      type = lib.types.submodule {
        options = wrapperType {
          name = "AWS CLI";
          defaultPkg = pkgs.awscli2;
        };
      };
      default = {};
      description = "AWS CLI wrapper configuration.";
    };

    opentofuWrapper = lib.mkOption {
      type = lib.types.submodule {
        options = wrapperType {
          name = "OpenTofu";
          defaultPkg = pkgs.opentofu;
        };
      };
      default = {};
      description = "OpenTofu wrapper configuration.";
    };

    terraformWrapper = lib.mkOption {
      type = lib.types.submodule {
        options = wrapperType {
          name = "Terraform";
          defaultPkg = pkgs.terraform;
        };
      };
      default = {};
      description = "Terraform wrapper configuration.";
    };
  };

  config = lib.mkIf (sp.enable && cfg.enable) (
    lib.mkMerge [
      # Core: always add aws-vault to devshell
      {
        stackpanel.devshell.packages = [ cfg.package ];

        # ── Module checks ──────────────────────────────────────────────
        stackpanel.moduleChecks.${meta.id} = {
          eval = {
            description = "aws-vault module evaluates without errors";
            required = true;
            derivation = pkgs.runCommand "sp-check-${meta.id}-eval" { } ''
              mkdir -p $out
              echo "aws-vault module evaluated successfully" > $out/result
            '';
          };
          packages = {
            description = "aws-vault packages are buildable";
            required = true;
            derivation =
              pkgs.runCommand "sp-check-${meta.id}-packages"
                {
                  buildInputs = [ cfg.package ];
                }
                ''
                  mkdir -p $out
                  echo "aws-vault packages OK" > $out/result
                '';
          };
        };

        # ── Health checks ──────────────────────────────────────────────
        stackpanel.healthchecks.modules.${meta.id} = {
          enable = true;
          displayName = meta.name;
          checks = {
            binary = {
              description = "aws-vault binary is available";
              check = ''
                if command -v aws-vault &>/dev/null; then
                  echo "aws-vault is available: $(aws-vault --version 2>&1)"
                else
                  echo "aws-vault binary not found"
                  exit 1
                fi
              '';
            };
            profile = {
              description = "AWS profile '${cfg.profile}' is configured";
              check = ''
                if aws-vault list --profiles 2>/dev/null | grep -q "^${cfg.profile}$"; then
                  echo "Profile '${cfg.profile}' exists"
                else
                  echo "Profile '${cfg.profile}' not found in aws-vault. Run: aws-vault add ${cfg.profile}"
                  exit 1
                fi
              '';
            };
          };
        };

        # ── Module registration ────────────────────────────────────────
        stackpanel.modules.${meta.id} = {
          enable = true;
          meta = {
            name = meta.name;
            description = meta.description;
            icon = meta.icon;
            category = meta.category;
            author = meta.author;
            version = meta.version;
            homepage = meta.homepage;
          };
          source.type = "builtin";
          features = meta.features;
          tags = meta.tags;
          priority = meta.priority;
          healthcheckModule = meta.id;
        };
      }

      # ── AWS CLI wrapper ──────────────────────────────────────────────
      (lib.mkIf cfg.awscliWrapper.enable {
        stackpanel.devshell.packages = [
          (mkWrapper {
            name = "aws";
            wrappedPkg = cfg.awscliWrapper.package;
          })
        ];
      })

      # ── OpenTofu wrapper ─────────────────────────────────────────────
      (lib.mkIf cfg.opentofuWrapper.enable {
        stackpanel.devshell.packages = [
          (mkWrapper {
            name = "tofu";
            wrappedPkg = cfg.opentofuWrapper.package;
          })
        ];
      })

      # ── Terraform wrapper ────────────────────────────────────────────
      (lib.mkIf cfg.terraformWrapper.enable {
        stackpanel.devshell.packages = [
          (mkWrapper {
            name = "terraform";
            wrappedPkg = cfg.terraformWrapper.package;
          })
        ];
      })
    ]
  );
}
