{
  lib,
  self ? null,
}:
let
  db = import ../../../db { inherit lib; };

  defaultLocalKey = {
    age-pub = "";
    ref = "ref+file://.stack/keys/local.txt";
  };

  masterKeyModule =
    { ... }:
    {
      options = db.asOptions db.extend.masterKey;
    };

  recipientModule =
    { ... }:
    {
      options = {
        public-key = lib.mkOption {
          type = lib.types.str;
          description = ''
            Public key to include in the generated `.stack/secrets/.sops.yaml`.

            Supports both AGE (`age1...`) and SSH Ed25519 (`ssh-ed25519 ...`) recipients.
          '';
          example = "age1psa52j93p0t7rej4lyzeww6hzg9hh4ylxu6v30tcgag44apw8als2xg3ef";
        };

        tags = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = ''
            Tags used to select this recipient for secret groups.

            A secret group includes every recipient whose tags overlap with the
            group's configured tags.
          '';
          example = [
            "dev"
            "shared"
          ];
        };
      };
    };

  recipientGroupModule =
    { ... }:
    {
      options = {
        recipients = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = ''
            Named recipients included by this reusable recipient group.
          '';
          example = [
            "alice"
            "buildkite"
          ];
        };
      };
    };

  creationRuleModule =
    { ... }:
    {
      options = {
        path-regex = lib.mkOption {
          type = lib.types.str;
          description = "Regex matched against SOPS file paths.";
          example = "^dev/web\\.sops\\.yaml$";
        };

        recipients = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Direct recipient names included in this rule.";
          example = [ "alice" ];
        };

        recipient-groups = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Named recipient groups expanded into this rule.";
          example = [
            "dev-team"
            "ci"
          ];
        };

        unencrypted-comment-regex = lib.mkOption {
          type = lib.types.str;
          default = ''^\s?(safe|plaintext)'';
          description = "Regex for comments that mark plaintext values in SOPS files.";
        };
      };
    };

  sopsAgeKeySourceModule =
    { ... }:
    {
      options = {
        id = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Optional UI identifier for this source.";
        };

        type = lib.mkOption {
          type = lib.types.enum [
            "user-key-path"
            "repo-key-path"
            "file"
            "ssh-key"
            "keychain"
            "aws-kms"
            "op-ref"
            "keyservice"
            "vals"
            "script"
          ];
          description = "Ordered source type used by sops-age-keys.";
        };

        value = lib.mkOption {
          type = lib.types.str;
          description = "Path or reference value for this source.";
        };

        enabled = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether this source is active.";
        };

        name = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Optional UI label for this source.";
        };

        priority = lib.mkOption {
          type = lib.types.nullOr lib.types.int;
          default = null;
          description = "Optional UI ordering metadata for this source.";
        };

        account = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Optional account selector for sources that support it, such as 1Password or macOS Keychain.";
        };
      };
    };

  # Derive recipients from stackpanel.users entries that include public keys.
  derivedRecipientsFromUsers =
    users:
    lib.foldl' lib.recursiveUpdate { } (
      lib.mapAttrsToList (
        userName: user:
        let
          keys = user.public-keys or [ ];
          tags = user.secrets-allowed-environments or [ ];
          mkRecipientName = index: if index == 0 then userName else "${userName}_${toString (index + 1)}";
        in
        lib.listToAttrs (
          lib.imap0 (index: publicKey: {
            name = mkRecipientName index;
            value = {
              public-key = publicKey;
              inherit tags;
            };
          }) keys
        )
      ) users
    );
in
{
  inherit
    db
    defaultLocalKey
    masterKeyModule
    recipientModule
    recipientGroupModule
    creationRuleModule
    sopsAgeKeySourceModule
    derivedRecipientsFromUsers
    ;
}
