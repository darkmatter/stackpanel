# ==============================================================================
# secrets.nix
#
# Master key-based secrets management.
#
# This module imports options from the proto schema (db/schemas/secrets.proto.nix)
# and extends them with Nix-specific runtime options.
#
# The proto schema is the SINGLE SOURCE OF TRUTH for the data structure.
#
# Groups:
#   Secrets groups provide access control boundaries. Each group has an AGE
#   keypair with the private key stored externally (e.g., SSM Parameter Store).
#   IAM policies control who can retrieve the private key, thereby controlling
#   who can decrypt secrets encrypted to that group.
#
#   Default groups: dev, prod
#
#   When a group is initialized (via `secrets:init-group <name>`):
#   1. An AGE keypair is generated
#   2. The private key is stored in SSM at the group's ssm-path
#   3. The public key is written to config so SOPS can encrypt to it
#   4. A corresponding master-key entry is auto-created for decryption
# ==============================================================================
{ lib, config, ... }:
let
  # Import the db module to get proto-derived options
  db = import ../../db { inherit lib; };

  # Variables backend config
  variablesBackend = config.stackpanel.secrets.backend or "vals";
  isChamber = variablesBackend == "chamber";
  chamberCfg = config.stackpanel.secrets.chamber or { };
  chamberPrefix = chamberCfg.service-prefix or (config.stackpanel.name or "my-project");

  # Default local key configuration
  defaultLocalKey = {
    age-pub = ""; # computed at runtime from private key
    ref = "ref+file://.stack/keys/local.txt";
  };

  # Master key submodule using proto-derived options
  masterKeyModule =
    { ... }:
    {
      options = db.asOptions db.extend.masterKey;
    };

  # Secrets group submodule using proto-derived options + computed fields
  secretsGroupModule =
    { name, config, ... }:
    {
      options = (db.asOptions db.extend.secretsGroup) // {
        # Computed: full vals reference for this group's private key
        computed-ref = lib.mkOption {
          type = lib.types.str;
          readOnly = true;
          description = "Computed vals reference for the group's AGE private key.";
        };
      };

      config = {
        # Default SSM path: /{service-prefix}/keys/{group-name}
        ssm-path = lib.mkDefault "/${chamberPrefix}/keys/${name}";

        # Default vals ref: computed from ssm-path
        ref = lib.mkDefault "ref+awsssm://${config.ssm-path}";

        # Computed ref always reflects the final ref value
        computed-ref = config.ref or "ref+awsssm://${config.ssm-path}";

        # Default key-cmd: decrypt .enc.age with sops (plain .age files are loaded globally by sops-age-keys)
        key-cmd = lib.mkDefault "sops --decrypt .stack/secrets/recipients/${name}.enc.age";
      };
    };

  # Default groups
  defaultGroups = {
    dev = { };
    prod = { };
  };

  # Computed: groups that have public keys configured (initialized)
  # age-pub is an optional proto field (defaults to null), so we must
  # check for both null and empty string.
  initializedGroups = lib.filterAttrs (
    _: g:
    let
      pub = g.age-pub or "";
    in
    pub != null && pub != ""
  ) (config.stackpanel.secrets.groups or { });

  # Auto-create master-key entries from initialized groups
  groupMasterKeys = lib.mapAttrs (name: group: {
    age-pub = group.age-pub;
    ref = group.computed-ref;
  }) initializedGroups;
in
{
  options.stackpanel.secrets =
    # Base options from proto schema (enable, secrets-dir)
    # Note: We override master-keys and groups to add submodules and defaults
    (lib.filterAttrs (n: _: n != "master-keys" && n != "groups") (db.asOptions db.extend.secrets)) // {
      # Override master-keys with our submodule that uses proto-derived options
      master-keys = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule masterKeyModule);
        default = {
          local = defaultLocalKey;
        };
        description = ''
          Master keys for encrypting/decrypting secrets.

          Each secret (variable with type=SECRET) specifies which master keys
          can decrypt it via the `master-keys` field. The .age file is encrypted
          to ALL specified master keys as recipients.

          A default "local" key is auto-generated in .stack/keys/
          ensuring secrets can always be created without external configuration.

          NOTE: Initialized secrets groups automatically create master-key entries.
          You do not need to manually add group keys here.
        '';
        example = lib.literalExpression ''
          {
            local = {
              age-pub = "age1...";
              ref = "ref+file://.stack/keys/local.txt";
            };
            dev = {
              age-pub = "age1...";
              ref = "ref+awsssm://my-org/my-repo/keys/dev";
            };
            prod = {
              age-pub = "age1...";
              ref = "ref+awsssm://my-org/my-repo/keys/prod";
            };
          }
        '';
      };

      # Override groups with our submodule that uses proto-derived options + defaults
      groups = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule secretsGroupModule);
        default = defaultGroups;
        description = ''
          Secrets groups for access control.

          Each group has its own AGE keypair. The private key is stored externally
          (e.g., AWS SSM Parameter Store) so that IAM policies control who can
          decrypt that group's secrets.

          Default groups: dev, prod

          After defining groups, initialize them with:
            secrets:init-group dev
            secrets:init-group prod

          This generates an AGE keypair, stores the private key in SSM, and
          writes the public key to your config.
        '';
        example = lib.literalExpression ''
          {
            dev = {
              age-pub = "age1abc...";  # set after init
            };
            prod = {
              age-pub = "age1xyz...";  # set after init
              ssm-path = "/custom/path/keys/prod";  # override default
            };
          }
        '';
      };

      # Computed: all public keys from all master keys
      all-public-keys = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        readOnly = true;
        description = "List of all master key public keys (computed, includes group keys).";
      };
    };

  config = lib.mkIf config.stackpanel.secrets.enable {
    # Auto-merge group-derived master keys with user-defined master keys.
    # We use mkDefault so user-defined keys in config.nix take priority.
    # The local key default is re-included here because setting the option
    # in config (even via mkDefault) overrides the option-level default.
    stackpanel.secrets.master-keys = lib.mkDefault ({ local = defaultLocalKey; } // groupMasterKeys);

    # Compute list of all public keys (includes both explicit master keys and group keys)
    stackpanel.secrets.all-public-keys = lib.pipe config.stackpanel.secrets.master-keys [
      (lib.mapAttrsToList (_: key: key.age-pub))
      (lib.filter (k: k != ""))
    ];
  };
}
