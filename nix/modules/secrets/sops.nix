# SOPS secrets management - generates .sops.yaml and secrets/{env}.yaml files
# Standalone module - no flake-parts dependency
#
# Philosophy: Use standard SOPS workflow, no new commands to learn
#   - sops secrets/dev.yaml         # edit dev secrets
#   - sops secrets/production.yaml  # edit prod secrets
#   - git add secrets/*.yaml        # encrypted files safe to commit
#
# Supports:
#   - secrets/{dev,staging,production,common}.yaml - committed, encrypted
#   - secrets/{env}.local.yaml - gitignored, for local overrides
#
{
  lib,
  config,
  pkgs,
  ...
}: let
  cfg = config.stackpanel.secrets;

  # YAML generation
  yaml = pkgs.formats.yaml {};
  toYaml = attrs: builtins.readFile (yaml.generate "sops.yaml" attrs);

  # All admins get access to all secrets automatically
  admins = lib.filterAttrs (_: u: u.admin or false) cfg.users;
  adminKeys = lib.mapAttrsToList (_: u: u.pubkey) admins;

  # All user keys for "common" environment
  allUserKeys = lib.mapAttrsToList (_: u: u.pubkey) cfg.users;

  # AGE key regex (matches age1...)
  isAgeKey = key: lib.hasPrefix "age1" key;

  # Get keys for a specific environment
  getEnvKeys = env: let
    envCfg = cfg.environments.${env} or {};
    explicitKeys = map (name: cfg.users.${name}.pubkey) (envCfg.users or []);
  in
    lib.unique (explicitKeys ++ adminKeys ++ (envCfg.extraKeys or []));

  # Generate .sops.yaml content
  sopsYamlContent = let
    # Build creation rules for each environment
    envRules =
      lib.mapAttrsToList (env: envCfg: let
        keys = getEnvKeys env;
        ageKeys = lib.filter isAgeKey keys;
      in {
        path_regex = "secrets/${env}(\\.local)?\\.yaml$";
        age = lib.concatStringsSep "," ageKeys;
      })
      cfg.environments;

    # Common secrets - all users have access
    commonRule = {
      path_regex = "secrets/common(\\.local)?\\.yaml$";
      age = lib.concatStringsSep "," (lib.filter isAgeKey allUserKeys);
    };
  in {creation_rules = [commonRule] ++ envRules;};

  # Placeholder content for new secrets files
  secretsPlaceholder = env: ''
    # ${env} secrets - edit with: sops secrets/${env}.yaml
    #
    # Example structure:
    # database:
    #   password: "your-db-password"
    # api_keys:
    #   stripe: "sk_live_..."
    #   sendgrid: "SG...."
    #
    # Local overrides: create secrets/${env}.local.yaml (gitignored)
  '';

  # Gitignore content for secrets directory
  secretsGitignore = ''
    # Local secret overrides - never commit
    *.local.yaml

    # Decrypted secrets - never commit
    *.dec.yaml
    *.decrypted.yaml

    # Editor backups
    *~
    *.swp
  '';
in {
  options.stackpanel.secrets = {
    enable = lib.mkEnableOption "SOPS secrets management";

    users = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          pubkey = lib.mkOption {
            type = lib.types.str;
            description = "AGE public key (age1...) or SSH public key";
          };
          github = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "GitHub username (for display/lookup)";
          };
          admin = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Admin users can decrypt all secrets";
          };
        };
      });
      default = {};
      example = lib.literalExpression ''
        {
          alice = { pubkey = "age1..."; github = "alice"; admin = true; };
          bob = { pubkey = "age1..."; github = "bobdev"; };
        }
      '';
      description = "Team members and their AGE public keys";
    };

    environments = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          users = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = "User names who can access this environment's secrets";
          };
          extraKeys = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = "Additional AGE keys (CI systems, servers)";
          };
        };
      });
      default = {
        dev = {};
        staging = {};
        production = {};
      };
      example = lib.literalExpression ''
        {
          dev = { users = [ "alice" "bob" "charlie" ]; };
          staging = { users = [ "alice" "bob" ]; };
          production = {
            users = [ "alice" ];
            extraKeys = [ "age1..." ];  # CI key
          };
        }
      '';
      description = "Environment configurations for secrets access";
    };

    secretsDir = lib.mkOption {
      type = lib.types.str;
      default = "secrets";
      description = "Directory for encrypted secrets files";
    };

    generatePlaceholders = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Generate placeholder .yaml files for each environment";
    };
  };

  config = lib.mkIf cfg.enable {
    stackpanel.files =
      {
        # .sops.yaml - SOPS configuration at repo root
        ".sops.yaml" = toYaml sopsYamlContent;

        # secrets/.gitignore - ignore local overrides
        "${cfg.secretsDir}/.gitignore" = secretsGitignore;

        # secrets/README.md - usage instructions
        "${cfg.secretsDir}/README.md" = ''
          # Secrets

          Encrypted with [SOPS](https://github.com/getsops/sops) + AGE.

          ## Usage

          ```bash
          # Edit secrets for an environment
          sops secrets/dev.yaml
          sops secrets/staging.yaml
          sops secrets/production.yaml

          # Common secrets (shared across all environments)
          sops secrets/common.yaml
          ```

          ## Local Overrides

          Create `secrets/{env}.local.yaml` for local-only secrets (gitignored):

          ```bash
          # Copy dev secrets as a starting point
          sops -d secrets/dev.yaml > secrets/dev.local.yaml
          # Edit as needed, then encrypt
          sops -e -i secrets/dev.local.yaml
          ```

          ## In Code

          Use [sops exec-env](https://github.com/getsops/sops#exec-env) to load secrets:

          ```bash
          # Run with dev secrets
          sops exec-env secrets/dev.yaml './start-server.sh'

          # Or with local overrides (if exists)
          sops exec-env secrets/dev.local.yaml './start-server.sh'
          ```

          ## Adding Team Members

          1. Get their AGE public key: `age-keygen -y ~/.age/key.txt`
          2. Add to `flake.nix` under `stackpanel.secrets.users`
          3. Run `nix run .#generate`
          4. Re-encrypt secrets: `sops updatekeys secrets/dev.yaml`
        '';
      }
      // lib.optionalAttrs cfg.generatePlaceholders (
        # Generate placeholder files for each environment
        lib.mapAttrs' (env: _:
          lib.nameValuePair "${cfg.secretsDir}/${env}.yaml"
          (secretsPlaceholder env))
        cfg.environments
        // {
          "${cfg.secretsDir}/common.yaml" = secretsPlaceholder "common";
        }
      );
  };
}
