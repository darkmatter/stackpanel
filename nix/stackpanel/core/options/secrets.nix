# ==============================================================================
# secrets.nix
#
# Master key-based secrets management.
#
# This module imports options from the proto schema (db/schemas/secrets.proto.nix)
# and extends them with Nix-specific runtime options.
#
# The proto schema is the SINGLE SOURCE OF TRUTH for the data structure.
# ==============================================================================
{ lib, config, ... }:
let
  # Import the db module to get proto-derived options
  db = import ../../db { inherit lib; };

  # Default local key configuration
  defaultLocalKey = {
    age-pub = ""; # computed at runtime from private key
    ref = "ref+file://.stackpanel/state/keys/local.txt";
  };

  # Master key submodule using proto-derived options
  masterKeyModule = { ... }: {
    options = db.asOptions db.extend.masterKey;
  };
in
{
  options.stackpanel.secrets =
    # Base options from proto schema (enable, secrets-dir)
    # Note: We override master-keys to add our submodule and defaults
    (lib.filterAttrs (n: _: n != "master-keys") (db.asOptions db.extend.secrets))
    // {
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
          
          A default "local" key is auto-generated in .stackpanel/state/keys/
          ensuring secrets can always be created without external configuration.
        '';
        example = lib.literalExpression ''
          {
            local = {
              age-pub = "age1...";
              ref = "ref+file://.stackpanel/state/keys/local.txt";
            };
            dev = {
              age-pub = "age1...";
              ref = "ref+awsssm://stackpanel/keys/dev";
            };
            prod = {
              age-pub = "age1...";
              ref = "ref+awsssm://stackpanel/keys/prod";
            };
          }
        '';
      };

      # Computed: all public keys from all master keys
      all-public-keys = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        readOnly = true;
        description = "List of all master key public keys (computed).";
      };
    };

  config = lib.mkIf config.stackpanel.secrets.enable {
    # Compute list of all public keys
    stackpanel.secrets.all-public-keys = lib.pipe config.stackpanel.secrets.master-keys [
      (lib.mapAttrsToList (_: key: key.age-pub))
      (lib.filter (k: k != ""))
    ];
  };
}
