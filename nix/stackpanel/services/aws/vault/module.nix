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

    profiles = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        List of AWS profiles to try in order.
        If specified, commands will try each profile until one succeeds.
        Leave empty to use only the single 'profile' option.
      '';
      example = [
        "production"
        "staging"
        "readonly"
      ];
    };

    stopOnFirstSuccess = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Stop trying profiles after the first successful command";
    };

    showProfileAttempts = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Show which profile is being attempted";
    };

    debug = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Enable debug logging for aws-vault wrapper calls.
        Logs to ~/.aws-vault-debug.log to help diagnose password prompt issues.
      '';
    };

    awsProfiles = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            region = lib.mkOption {
              type = lib.types.str;
              default = "us-west-2";
              description = "AWS region for this profile";
            };

            roleArn = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "IAM role ARN to assume";
              example = "arn:aws:iam::123456789012:role/MyRole";
            };

            sourceProfile = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Source profile to use for credentials";
              example = "default";
            };

            output = lib.mkOption {
              type = lib.types.nullOr (
                lib.types.enum [
                  "json"
                  "yaml"
                  "text"
                  "table"
                ]
              );
              default = null;
              description = "Default output format";
            };

            mfaSerial = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "MFA device ARN";
              example = "arn:aws:iam::123456789012:mfa/user";
            };

            durationSeconds = lib.mkOption {
              type = lib.types.nullOr lib.types.int;
              default = null;
              description = "Session duration in seconds";
              example = 3600;
            };

            extraConfig = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
              default = { };
              description = "Additional configuration options";
              example = {
                cli_pager = "";
                s3_max_concurrent_requests = "20";
              };
            };
          };
        }
      );
      default = { };
      description = ''
        AWS profiles to configure programmatically.
        These will be converted to ~/.aws/config format.

        Example:
          awsProfiles = {
            default = {
              region = "us-west-2";
              output = "json";
            };
            production = {
              region = "us-east-1";
              roleArn = "arn:aws:iam::123456789012:role/ProdRole";
              sourceProfile = "default";
              mfaSerial = "arn:aws:iam::123456789012:mfa/user";
            };
          };
      '';
    };

    configFile = lib.mkOption {
      type = lib.types.nullOr lib.types.lines;
      default = null;
      description = ''
        Contents to write to ~/.aws/config.
        If null, the file is not managed by Stackpanel.

        This will be written to the file on shell entry.

        Example:
          configFile = '''
            [default]
            region = us-west-2
            output = json

            [profile production]
            region = us-east-1
            role_arn = arn:aws:iam::123456789012:role/ProductionRole
            source_profile = default

            [profile staging]
            region = us-east-1
            role_arn = arn:aws:iam::123456789012:role/StagingRole
            source_profile = default
          ''';
      '';
      example = ''
        [default]
        region = us-west-2

        [profile production]
        region = us-east-1
        role_arn = arn:aws:iam::123456789012:role/ProdRole
        source_profile = default
      '';
    };

    generateConfigFile = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to automatically generate ~/.aws/config from awsProfiles.
        Set to false if you want to manage the file manually or use configFile directly.
      '';
    };

    awscliWrapper = lib.mkOption {
      type = lib.types.submodule {
        options = wrapperType {
          name = "AWS CLI";
          defaultPkg = pkgs.awscli2;
        };
      };
      default = { };
      description = "AWS CLI wrapper configuration.";
    };

    opentofuWrapper = lib.mkOption {
      type = lib.types.submodule {
        options = wrapperType {
          name = "OpenTofu";
          defaultPkg = pkgs.opentofu;
        };
      };
      default = { };
      description = "OpenTofu wrapper configuration.";
    };

    terraformWrapper = lib.mkOption {
      type = lib.types.submodule {
        options = wrapperType {
          name = "Terraform";
          defaultPkg = pkgs.opentofu;
        };
      };
      default = { };
      description = "Terraform wrapper configuration.";
    };
  };

  config = lib.mkIf (sp.enable && cfg.enable) (
    let
      # Generate AWS config file content from awsProfiles
      generateAwsConfig =
        profiles:
        let
          formatProfile =
            name: profileCfg:
            let
              header = if name == "default" then "[default]" else "[profile ${name}]";

              settings =
                lib.filterAttrs (_: v: v != null) {
                  region = profileCfg.region;
                  role_arn = profileCfg.roleArn;
                  source_profile = profileCfg.sourceProfile;
                  output = profileCfg.output;
                  mfa_serial = profileCfg.mfaSerial;
                  duration_seconds =
                    if profileCfg.durationSeconds != null then toString profileCfg.durationSeconds else null;
                }
                // profileCfg.extraConfig;

              settingsLines = lib.mapAttrsToList (k: v: "${k} = ${v}") settings;
            in
            ''
              ${header}
              ${lib.concatStringsSep "\n" settingsLines}
            '';
        in
        lib.concatStringsSep "\n\n" (lib.mapAttrsToList formatProfile profiles);

      # Determine final config file content
      finalConfigFile =
        if cfg.configFile != null then
          cfg.configFile
        else if cfg.awsProfiles != { } && cfg.generateConfigFile then
          generateAwsConfig cfg.awsProfiles
        else
          null;

      # Helper to create a wrapper that tries multiple profiles
      mkMultiProfileWrapper =
        { name, wrappedPkg }:
        if cfg.profiles != [ ] then
          pkgs.writeScriptBin name ''
            #!${pkgs.bash}/bin/bash
            set -e

            ${lib.optionalString cfg.debug ''
              echo "[$(date)] ${name} called with args: $*" >> ~/.aws-vault-debug.log
            ''}

            PROFILES=(${lib.concatMapStringsSep " " lib.escapeShellArg cfg.profiles})
            LAST_EXIT_CODE=1

            for profile in "''${PROFILES[@]}"; do
              ${lib.optionalString cfg.showProfileAttempts ''
                echo "→ Trying AWS profile: $profile" >&2
              ''}

              ${lib.optionalString cfg.debug ''
                echo "[$(date)] Trying profile: $profile for ${name}" >> ~/.aws-vault-debug.log
              ''}

              if ${lib.getExe cfg.package} exec "$profile" -- ${lib.getExe wrappedPkg} "$@" 2>&1; then
                ${lib.optionalString cfg.showProfileAttempts ''
                  echo "✓ Success with profile: $profile" >&2
                ''}
                ${lib.optionalString cfg.debug ''
                  echo "[$(date)] Success with profile: $profile" >> ~/.aws-vault-debug.log
                ''}
                ${lib.optionalString cfg.stopOnFirstSuccess "exit 0"}
                LAST_EXIT_CODE=0
              else
                LAST_EXIT_CODE=$?
                ${lib.optionalString cfg.showProfileAttempts ''
                  echo "✗ Failed with profile: $profile (exit code: $LAST_EXIT_CODE)" >&2
                ''}
                ${lib.optionalString cfg.debug ''
                  echo "[$(date)] Failed with profile: $profile (exit: $LAST_EXIT_CODE)" >> ~/.aws-vault-debug.log
                ''}
              fi
            done

            if [ $LAST_EXIT_CODE -ne 0 ]; then
              echo "" >&2
              echo "✗ All profiles failed" >&2
              echo "Tried: ${lib.concatStringsSep ", " cfg.profiles}" >&2
            fi

            exit $LAST_EXIT_CODE
          ''
        else
          mkWrapper { inherit name wrappedPkg; };

      # Scripts for working with multiple profiles
      multiProfileScripts = lib.optionalAttrs (cfg.profiles != [ ]) {
        "aws-vault:list-profiles" = {
          exec = ''
            echo "AWS Vault Profiles (in order):"
            echo ""
            ${lib.concatMapStringsSep "\n" (profile: ''
              echo "  ${profile}:"
              if aws-vault list --profiles 2>/dev/null | grep -q "^${profile}$"; then
                echo "    Status: ✓ Configured"
              else
                echo "    Status: ✗ Not configured (run: aws-vault add ${profile})"
              fi
            '') cfg.profiles}
            echo ""
            echo "Default profile: ${cfg.profile}"
          '';
          description = "List configured AWS Vault profiles";
        };

        "aws-vault:with-profile" = {
          exec = ''
            if [ $# -lt 2 ]; then
              echo "Usage: aws-vault:with-profile <profile> <command> [args...]" >&2
              echo "" >&2
              echo "Available profiles: ${lib.concatStringsSep ", " cfg.profiles}" >&2
              exit 1
            fi

            PROFILE="$1"
            shift

            ${lib.optionalString cfg.debug ''
              echo "[$(date)] aws-vault:with-profile called: $PROFILE with args: $*" >> ~/.aws-vault-debug.log
            ''}

            echo "→ Using AWS profile: $PROFILE" >&2
            exec ${lib.getExe cfg.package} exec "$PROFILE" -- "$@"
          '';
          description = "Run command with specific AWS Vault profile";
        };
      };
    in
    lib.mkMerge [
      # Core: always add aws-vault to devshell
      {
        stackpanel.devshell.packages = [ cfg.package ];

        # Add multi-profile helper scripts if enabled
        stackpanel.scripts = multiProfileScripts;

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
              script = ''
                if command -v aws-vault &>/dev/null; then
                  echo "aws-vault is available: $(aws-vault --version 2>&1)"
                else
                  echo "aws-vault binary not found"
                  exit 1
                fi
              '';
            };
            # Note: Profile checks are disabled by default to avoid keychain password prompts
            # Enable by setting stackpanel.healthchecks.modules.aws-vault.checks.profile.enable = true
            profile = lib.mkIf false {
              description = "AWS profile '${cfg.profile}' is configured (disabled to avoid keychain prompts)";
              script = ''
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
          flakeInputs = meta.flakeInputs or [ ];
          tags = meta.tags;
          priority = meta.priority;
          healthcheckModule = meta.id;
        };
      }

      # ── AWS Config File Generation ─────────────────────────────────
      (lib.mkIf (finalConfigFile != null) {
        stackpanel.devshell.hooks.before = [
          ''
            # Generate ~/.aws/config from Nix configuration
            AWS_CONFIG_DIR="''${HOME}/.aws"
            AWS_CONFIG_FILE="''${AWS_CONFIG_DIR}/config"

            mkdir -p "''${AWS_CONFIG_DIR}"
            chmod 700 "''${AWS_CONFIG_DIR}"

            # Write config file
            cat > "''${AWS_CONFIG_FILE}" << 'EOF'
            ${finalConfigFile}
            EOF

            chmod 600 "''${AWS_CONFIG_FILE}"
          ''
        ];
      })

      # ── AWS CLI wrapper ──────────────────────────────────────────────
      (lib.mkIf cfg.awscliWrapper.enable {
        stackpanel.devshell.packages = [
          (mkMultiProfileWrapper {
            name = "aws";
            wrappedPkg = cfg.awscliWrapper.package;
          })
        ];
      })

      # ── OpenTofu wrapper ─────────────────────────────────────────────
      (lib.mkIf cfg.opentofuWrapper.enable {
        stackpanel.devshell.packages = [
          (mkMultiProfileWrapper {
            name = "tofu";
            wrappedPkg = cfg.opentofuWrapper.package;
          })
        ];
      })

      # ── Terraform wrapper ────────────────────────────────────────────
      (lib.mkIf cfg.terraformWrapper.enable {
        stackpanel.devshell.packages = [
          (mkMultiProfileWrapper {
            name = "terraform";
            wrappedPkg = cfg.terraformWrapper.package;
          })
        ];
      })
    ]
  );
}
