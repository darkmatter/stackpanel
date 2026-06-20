{
  lib,
}:
let
  db = import ../../../db { inherit lib; };

  defaultLocalKey = {
    age-pub = "";
    ref = "ref+file://.stack/keys/local.txt";
  };

  masterKeyModule = _: {
    options = db.asOptions db.extend.masterKey;
  };

  recipientModule = _: {
    options = {
      public-key = lib.mkOption {
        type = lib.types.str;
        description = ''
          Public key to include in the generated repo-root `.sops.yaml`.

          Supports both AGE (`age1...`) and SSH Ed25519 (`ssh-ed25519 ...`) recipients.
          The recipient attribute name is what creation rules and recipient groups
          reference.
        '';
        example = "age1psa52j93p0t7rej4lyzeww6hzg9hh4ylxu6v30tcgag44apw8als2xg3ef";
      };

      tags = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          Human-readable labels for this recipient, usually environments or roles.

          Tags are metadata for UI and inventory. SOPS creation rules select
          recipients by explicit name or by `recipient-groups`; they do not expand
          tags directly.
        '';
        example = [
          "dev"
          "shared"
        ];
      };
    };
  };

  recipientGroupModule = _: {
    options = {
      recipients = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          Named recipients included by this reusable recipient group.

          Values are recipient attribute names, for example `alice` from
          `stackpanel.secrets.recipients.alice` or a derived user recipient name.
        '';
        example = [
          "alice"
          "buildkite"
        ];
      };
    };
  };

  creationRuleModule = _: {
    options = {
      path-regex = lib.mkOption {
        type = lib.types.str;
        description = ''
          Regex matched by SOPS against encrypted file paths.

          For Stackpanel variables, match `.stack/secrets/vars/<group>.sops.yaml`.
          Keep narrow environment rules before catch-all rules.
        '';
        example = "^\\.stack/secrets/vars/dev\\.sops\\.yaml$";
      };

      recipients = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          Direct recipient names included in this creation rule.

          Names must exist in `stackpanel.secrets.recipients` or be derived from
          `stackpanel.users.*.public-keys`.
        '';
        example = [ "deploy_bot" ];
      };

      recipient-groups = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          Named recipient groups expanded into this creation rule.

          Each name must exist in `stackpanel.secrets.recipient-groups`.
        '';
        example = [
          "dev-team"
          "ci"
        ];
      };

      unencrypted-comment-regex = lib.mkOption {
        type = lib.types.str;
        default = ".*";
        description = ''
          Regex for comments that should be stored in plaintext inside SOPS
          files. Defaults to ".*" so every comment is preserved as plaintext
          metadata; the studio UI surfaces these comments as descriptions.
        '';
      };
    };
  };

  sopsAgeKeySourceModule = _: {
    options = {
      id = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Optional stable UI identifier for this key source.";
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
        description = ''
          Ordered source type used by `sops-age-keys`.

          File-like sources use `value` as a path. Reference sources use `value` as
          the external ref. `script` executes `value` and expects an AGE private key
          on stdout.
        '';
      };

      value = lib.mkOption {
        type = lib.types.str;
        description = "Path, external reference, keyservice URL, or command for this source.";
      };

      enabled = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether this SOPS AGE key source should be tried during key discovery.";
        example = false;
      };

      name = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Optional human-readable UI label for this source.";
      };

      priority = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = "Optional UI ordering metadata; list order remains authoritative.";
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
