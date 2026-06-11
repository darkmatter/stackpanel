{
  lib,
  pkgs,
  config,
  cfg,
  isChamber,
  chamberCfg,
  variablesBackend,
  sopsAgeKeyPaths,
  sopsAgeKeyOpRefs,
  sopsKeyservices,
  recipientNames,
  recipientsConfig,
  normalizedRecipientPubkeys,
  sshEd25519RecipientKeys,
  secretFilesMeta,
  manifestJson,
  cfgLib,
  sopsConfigText,
  secretsLib,
  sopsAgeKeys,
  sopsWrapped,
  secretsSet,
  secretsGet,
  secretsList,
  secretsRekey,
  secretsLoad,
  sopsAgeKeychainSave,
  sopsAgeRecipientsInit,
  rekeyScriptText,
  legacySecretsCleanupScript,
}: let
  groupByFile =
    lib.mapAttrs' (
      variableId: meta: let
        groupName = lib.removeSuffix ".sops.yaml" (builtins.baseNameOf meta.file);
      in {
        name = groupName;
        value = {
          tags = lib.unique meta.tags;
          recipients = lib.unique meta.recipients;
        };
      }
    )
    secretFilesMeta;
in {
  config = lib.mkIf cfg.enable {
    stackpanel = {
      devshell.packages = lib.mkBefore (
      [
        sopsWrapped
        sopsAgeKeys
        sopsAgeKeychainSave
        sopsAgeRecipientsInit
        pkgs.age
        pkgs.ssh-to-age
        pkgs.vals
        pkgs.jq
        secretsSet
        secretsGet
        secretsList
        secretsRekey
        secretsLoad
      ]
        ++ lib.optional isChamber pkgs.chamber
      );
      devshell.env = lib.optionalAttrs isChamber {
        CHAMBER_KMS_KEY_ALIAS = "alias/${config.stackpanel.name or "my-project"}-secrets";
      };
    };


    stackpanel.devshell.hooks.before = [
      # Refresh the checked-in ssh-ed25519 -> age conversion cache consumed at
      # eval time by normalizeRecipientPublicKey (context.nix). Keeping the
      # cache current means pure cross-system evaluation (flakehub-push, CI)
      # never needs the import-from-derivation ssh-to-age fallback.
      ''
        (
        SSH_AGE_CACHE="''${STACKPANEL_ROOT:-.}/.stack/data/external/ssh-age-cache.json"
        mkdir -p "$(dirname "$SSH_AGE_CACHE")"
        new_cache="$(
          for ssh_key in ${lib.escapeShellArgs sshEd25519RecipientKeys}; do
            age_key="$(printf '%s\n' "$ssh_key" | ${pkgs.ssh-to-age}/bin/ssh-to-age 2>/dev/null || true)"
            [[ -z "$age_key" ]] && continue
            ${pkgs.jq}/bin/jq -n --arg k "$ssh_key" --arg v "$age_key" '{($k): $v}'
          done | ${pkgs.jq}/bin/jq -s 'add // {}'
        )"
        if [[ ! -f "$SSH_AGE_CACHE" ]] || ! printf '%s' "$new_cache" | ${pkgs.diffutils}/bin/diff -q "$SSH_AGE_CACHE" - >/dev/null 2>&1; then
          printf '%s\n' "$new_cache" > "$SSH_AGE_CACHE"
          echo "Updated .stack/data/external/ssh-age-cache.json (commit it so pure eval avoids ssh-to-age IFD)" >&2
        fi
        )
      ''
      ''
        (
        ${secretsLib.autoGenerateLocalKeyScript {
          configuredRecipientPubkeys = normalizedRecipientPubkeys;
          inherit sopsAgeKeys;
        }}
        )
      ''
      ''
        (
        ${legacySecretsCleanupScript}
        )
      ''
      ''
        (
        SECRETS_STATE_DIR="${cfg.secrets-dir}/state"
        mkdir -p "$SECRETS_STATE_DIR"
        MANIFEST_FILE="$SECRETS_STATE_DIR/manifest.json"
        echo ${lib.escapeShellArg manifestJson} > "$MANIFEST_FILE"
        )
      ''
    ];

    stackpanel.scripts = {
      "secrets:set" = {
        exec = "${secretsSet}/bin/secrets-set \"$@\"";
        description = "Set a secret value in a SOPS group file";
        args = [
          {
            name = "key";
            description = "Secret key name (e.g., api-key, database-url)";
            required = true;
          }
          {
            name = "--group";
            description = "Target group (defaults to dev)";
            default = "dev";
          }
          {
            name = "--value";
            description = "The secret value (reads from stdin if not provided)";
          }
        ];
      };

      "secrets:get" = {
        exec = "${secretsGet}/bin/secrets-get \"$@\"";
        description = "Get a decrypted secret value from a SOPS group file";
        args = [
          {
            name = "key";
            description = "Secret key name";
            required = true;
          }
          {
            name = "--group";
            description = "Source group (defaults to dev)";
            default = "dev";
          }
        ];
      };

      "secrets:list" = {
        exec = "${secretsList}/bin/secrets-list \"$@\"";
        description = "List all secrets across SOPS group files";
        args = [
          {
            name = "group";
            description = "Optional filter";
          }
        ];
      };

      "secrets:rekey" = {
        exec = "${secretsRekey}/bin/secrets-rekey \"$@\"";
        description = "Re-key a secret file to different master keys";
        args = [
          {
            name = "variable-id";
            description = "Secret variable ID";
            required = true;
          }
          {
            name = "--keys";
            description = "Comma-separated master key list";
            required = true;
          }
        ];
      };

      "secrets:load" = {
        exec = "${secretsLoad}/bin/secrets-load \"$@\"";
        description = "Decrypt a SOPS vars file (dotenv, json, or yaml)";
        args = [
          {
            name = "group";
            description = "Group to decrypt";
            required = true;
          }
          {
            name = "--format";
            description = "Output format: dotenv (default), json, yaml";
            default = "dotenv";
          }
        ];
      };

      "secrets:show-keys" = {
        exec = ''
          echo "Recipients:"
          ${lib.concatStringsSep "\n" (
            map (name: "echo \"  ${name}: ${recipientsConfig.${name}.public-key}\"") recipientNames
          )}
          echo ""
          echo "Groups:"
          ${lib.concatStringsSep "\n" (
            lib.mapAttrsToList (
              groupName: groupCfg: "echo \"  ${groupName}: ${builtins.toString groupCfg.recipients}\""
            )
            groupByFile
          )}
        '';
        description = "Show configured recipients and groups";
      };
    };

    stackpanel.devshell.hooks.main = [
      ''
        export SOPS_AGE_KEY_CMD="${sopsAgeKeys}/bin/sops-age-keys"
        ${lib.optionalString (
          sopsKeyservices != [ ]
        ) ''export SOPS_KEYSERVICE="${lib.concatStringsSep "," sopsKeyservices}"''}
      ''
    ];

    stackpanel.files.entries = lib.mkMerge [
      {
        ".gitignore" = {
          type = "line-set";
          managed = "block";
          dedupe = true;
          lines = [
            "${cfg.secrets-dir}/state/"
            "${cfg.secrets-dir}/bin/"
          ];
        };

        ".sops.yaml" = {
          type = "text";
          source = "secrets";
          text = sopsConfigText;
        };

        "${cfg.secrets-dir}/README.md" = {
          type = "text";
          source = "secrets";
          text = ''
            # Stackpanel Secrets

            This repository uses recipient-driven SOPS files in `${cfg.secrets-dir}`.

            - `vars/*.sops.yaml` stores encrypted values.
            - `<repo-root>/.sops.yaml` is generated from `stackpanel.secrets.recipients`
              and optional `stackpanel.secrets.creation-rules`. It lives at the repo
              root so editor extensions and `sops` discover it without `--config`.
            - Secrets are resolved using local key helper at shell entry.

            ## Recipient-driven groups

            Recipients are grouped by tags and tags are matched by creation rules.
            Use `secrets:show-keys` to inspect current recipient and group state.

            ## Files

            - `<repo-root>/.sops.yaml`
            - `${cfg.secrets-dir}/vars/*.sops.yaml`
            - `${cfg.secrets-dir}/bin/rekey.sh`
            - `${cfg.secrets-dir}/state/manifest.json` (generated)
          '';
        };

        "${cfg.secrets-dir}/bin/rekey.sh" = {
          type = "text";
          source = "secrets";
          mode = "0755";
          text = rekeyScriptText;
        };
      }
    ];


    stackpanel.serializable.secrets = {
      enable = cfg.enable;
      secretsDir = cfg.secrets-dir;
      sopsConfigFile = ".sops.yaml";

      recipients =
        lib.mapAttrs (_: recipient: {
          publicKey = recipient.public-key;
          tags = recipient.tags or [];
        })
        recipientsConfig;

      variables = secretFilesMeta;

      groups = groupByFile;
    };

    stackpanel.serializable.variables =
      {
        backend = variablesBackend;
      }
      // lib.optionalAttrs isChamber {
        chamber = {
          servicePrefix = chamberCfg.service-prefix;
        };
      };
  };
}
