{
  pkgs,
  lib,
  config,
}:
let
  cfg = config.stackpanel.secrets;
  variablesBackend = config.stackpanel.secrets.backend;
  isChamber = variablesBackend == "chamber";
  chamberCfg = config.stackpanel.secrets.chamber;
  # @impure — falls back to PWD when `config.stackpanel.root` isn't set.
  # The fallback only fires when the secrets module is evaluated outside the
  # normal flake entry (which always sets `stackpanel.root`). If you ever load
  # this module from `nix eval` without setting `stackpanel.root`, you'll need
  # `--impure` to read PWD.
  projectRoot =
    if config.stackpanel.root != null then config.stackpanel.root else builtins.getEnv "PWD"; # @impure
  kmsConfigPath = if projectRoot != "" then "${projectRoot}/.stack/state/kms-config.json" else "";
  kmsStateConfig =
    let
      empty = {
        enable = false;
        keyArn = "";
        awsProfile = "";
        roleArn = "";
      };
    in
    if kmsConfigPath != "" && builtins.pathExists kmsConfigPath then
      let
        parsed = builtins.fromJSON (builtins.readFile kmsConfigPath);
      in
      empty
      // {
        enable = if parsed ? enable then parsed.enable else false;
        keyArn = if parsed ? keyArn then parsed.keyArn else "";
        awsProfile = if parsed ? awsProfile then parsed.awsProfile else "";
        roleArn = if parsed ? roleArn then parsed.roleArn else "";
      }
    else
      empty;
  # Nix config takes precedence over state file
  nixKmsKeyArn = cfg.kms.key-arn or null;
  nixKmsAwsProfile = cfg.kms.aws-profile or null;
  nixKmsRoleArn = cfg.kms.aws-role-arn or null;
  kmsConfig =
    if nixKmsKeyArn != null && nixKmsKeyArn != "" then
      {
        enable = true;
        keyArn = nixKmsKeyArn;
        awsProfile = if nixKmsAwsProfile != null then nixKmsAwsProfile else "";
        roleArn = if nixKmsRoleArn != null then nixKmsRoleArn else "";
      }
    else
      kmsStateConfig;
  kmsEnabled = kmsConfig.enable && kmsConfig.keyArn != "";

  # Import cfg.nix for path resolution in shell hooks
  cfgLib = import ../../lib/cfg.nix { inherit lib; };

  # Import secrets library
  secretsLib = import ../lib.nix {
    inherit pkgs lib;
    secretsDir = cfg.secrets-dir;
  };

  normalizeVariableId =
    value:
    let
      raw = lib.removePrefix "var://" (builtins.toString value);
    in
    if lib.hasPrefix "/" raw then raw else "/${raw}";

  getVarName =
    id:
    let
      cleaned = lib.removePrefix "/" id;
      parts = lib.splitString "/" cleaned;
    in
    if parts != [ ] then lib.last parts else id;

  getKeyGroup =
    id:
    let
      cleaned = lib.removePrefix "/" id;
      parts = lib.splitString "/" cleaned;
    in
    if parts != [ ] then builtins.head parts else "var";

  secretFileStem = id: builtins.replaceStrings [ "/" "\\" " " ] [ "-" "-" "-" ] (getVarName id);

  secretYamlKey = id: builtins.replaceStrings [ "-" "." "/" " " ] [ "_" "_" "_" "_" ] (getVarName id);

  # Convert master-keys to the format expected by lib scripts
  masterKeysConfig = lib.mapAttrs (name: key: {
    inherit (key) age-pub ref;
    "resolve-cmd" = key."resolve-cmd" or "";
  }) cfg.master-keys;

  userRecipients = lib.foldl' lib.recursiveUpdate { } (
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
    ) config.stackpanel.users
  );

  recipientsConfig = userRecipients // cfg.recipients;
  recipientGroupsConfig = cfg.recipient-groups or { };
  creationRulesConfig = cfg.creation-rules or [ ];
  fallbackSopsAgeSources =
    lib.optional
      (cfg.sops-age-keys.user-key-path or null != null && cfg.sops-age-keys.user-key-path != "")
      {
        type = "user-key-path";
        value = cfg.sops-age-keys.user-key-path;
        enabled = true;
        name = "User key path";
      }
    ++
      lib.optional
        (cfg.sops-age-keys.repo-key-path or null != null && cfg.sops-age-keys.repo-key-path != "")
        {
          type = "repo-key-path";
          value = cfg.sops-age-keys.repo-key-path;
          enabled = true;
          name = "Repo key path";
        }
    ++ map (value: {
      type = "file";
      inherit value;
      enabled = true;
      name = "Extra file path";
    }) (cfg.sops-age-keys.paths or [ ])
    ++ map (value: {
      type = "op-ref";
      inherit value;
      enabled = true;
      name = "1Password ref";
    }) (cfg.sops-age-keys.op-refs or [ ]);

  sopsAgeSources =
    if (cfg.sops-age-keys.sources or [ ]) != [ ] then
      cfg.sops-age-keys.sources
    else
      fallbackSopsAgeSources;
  enabledSopsAgeSources = lib.filter (source: source.enabled or true) sopsAgeSources;
  sopsAgeUserKeyPath =
    let
      matches = lib.filter (source: source.type == "user-key-path") enabledSopsAgeSources;
    in
    if matches != [ ] then (lib.head matches).value else cfg.sops-age-keys.user-key-path or null;
  sopsAgeRepoKeyPath =
    let
      matches = lib.filter (source: source.type == "repo-key-path") enabledSopsAgeSources;
    in
    if matches != [ ] then (lib.head matches).value else cfg.sops-age-keys.repo-key-path or null;
  sourceFilePaths = map (source: source.value) (
    lib.filter (source: lib.elem source.type [ "file" ]) enabledSopsAgeSources
  );
  sourceOpRefs = map (source: source.value) (
    lib.filter (source: source.type == "op-ref") enabledSopsAgeSources
  );
  sourceKeyservices = map (source: source.value) (
    lib.filter (source: source.type == "keyservice") enabledSopsAgeSources
  );
  sopsAgeKeyPaths = lib.filter (x: x != null && x != "") (
    [
      sopsAgeUserKeyPath
      sopsAgeRepoKeyPath
    ]
    ++ sourceFilePaths
  );
  sopsAgeKeyOpRefs = sourceOpRefs;
  sopsKeyservices = sourceKeyservices;
  sopsAgeSourceLines = lib.concatMapStringsSep "\n" (
    source:
    "${source.type}\t${source.value}\t${
      if (source.account or null) != null then source.account else ""
    }"
  ) enabledSopsAgeSources;
  recipientNames = lib.sort lib.lessThan (lib.attrNames recipientsConfig);

  # AGE pubkeys for every configured recipient, with SSH ed25519 keys converted
  # via ssh-to-age. Used both to render .sops.yaml and to compare against the
  # local AGE key in the devshell warning — the raw `r.public-key` strings can
  # be in SSH format (collaborators synced from GitHub), so a literal string
  # match against the local AGE key would always miss.
  normalizedRecipientPubkeys = lib.unique (
    lib.mapAttrsToList (_: r: normalizeRecipientPublicKey r.public-key) recipientsConfig
  );

  # Normalize a recipient public key to AGE format for .sops.yaml.
  # SSH Ed25519 public keys are converted at eval time using ssh-to-age.
  # Other formats (RSA, ECDSA) are kept as-is since ssh-to-age only supports Ed25519.
  normalizeRecipientPublicKey =
    publicKey:
    let
      trimmed = lib.trim publicKey;
      sshToAge = pkgs.ssh-to-age;
    in
    if lib.hasPrefix "ssh-ed25519 " trimmed then
      lib.removeSuffix "\n" (
        builtins.readFile (
          pkgs.runCommand "ssh-to-age-${builtins.hashString "md5" trimmed}" { } ''
            printf '%s\n' ${lib.escapeShellArg trimmed} | ${sshToAge}/bin/ssh-to-age > $out
          ''
        )
      )
    else
      trimmed;

  normalizeAnchor =
    name: lib.replaceStrings [ "-" "." "/" "@" ":" "+" ] [ "_" "_" "_" "_" "_" "_" ] name;

  recipientTags = recipientName: recipientsConfig.${recipientName}.tags or [ ];

  expandRuleRecipients =
    rule:
    let
      direct = rule.recipients or [ ];
      grouped = lib.concatMap (groupName: (recipientGroupsConfig.${groupName}.recipients or [ ])) (
        rule.recipient-groups or [ ]
      );
      combined = lib.unique (direct ++ grouped);
    in
    if combined != [ ] then combined else recipientNames;

  appLinkTagsByVariable = lib.foldl' (
    acc: appName:
    let
      appCfg = config.stackpanel.apps.${appName};
      envs = appCfg.environments or { };
    in
    lib.foldl' (
      accEnv: envName:
      let
        envVars = envs.${envName}.env or { };
      in
      lib.foldl' (
        accVar: envKey:
        let
          strValue = builtins.toString envVars.${envKey};
        in
        if lib.hasPrefix "var://" strValue then
          let
            variableId = normalizeVariableId strValue;
            existing = accVar.${variableId} or [ ];
          in
          accVar
          // {
            ${variableId} = lib.unique (
              existing
              ++ [
                envName
                "${appName}/${envName}"
              ]
            );
          }
        else
          accVar
      ) accEnv (lib.attrNames envVars)
    ) acc (lib.attrNames envs)
  ) { } (lib.attrNames config.stackpanel.apps);

  secretVariables = lib.filterAttrs (_: v: v.isSecret) config.stackpanel.variables;
  secretIds = lib.sort lib.lessThan (lib.attrNames secretVariables);

  secretTags =
    variableId:
    let
      variable = secretVariables.${variableId};
      keyGroup = getKeyGroup variableId;
      linkTags = appLinkTagsByVariable.${variableId} or [ ];
      legacyTags =
        if keyGroup != "secret" && keyGroup != "var" && keyGroup != "computed" then [ keyGroup ] else [ ];
    in
    lib.unique (legacyTags ++ linkTags);

  secretRecipients =
    variableId:
    let
      tags = secretTags variableId;
    in
    if tags == [ ] then
      recipientNames
    else
      lib.filter (
        recipientName:
        let
          tagsForRecipient = recipientTags recipientName;
        in
        lib.any (tag: lib.elem tag tagsForRecipient) tags
      ) recipientNames;

  secretFilesMeta = lib.genAttrs secretIds (variableId: {
    # Group-based path: /dev/postgres-url → vars/dev.sops.yaml
    file = "vars/${getKeyGroup variableId}.sops.yaml";
    yamlKey = secretYamlKey variableId;
    tags = secretTags variableId;
    recipients = secretRecipients variableId;
  });

  # Merge all variables that share the same group file into one rule entry.
  secretFilesByGroup = lib.foldl' (
    acc: variableId:
    let
      file = secretFilesMeta.${variableId}.file;
      recipients = secretFilesMeta.${variableId}.recipients;
      existing = acc.${file} or [ ];
    in
    acc // { ${file} = lib.unique (existing ++ recipients); }
  ) { } secretIds;

  mkRuleLines =
    pathRegex: names: unencryptedCommentRegex:
    let
      ageLines =
        if names == [ ] then
          [ ]
        else
          [ "    age:" ] ++ map (name: "      - *${normalizeAnchor name}") names;
      # SOPS flat KMS format: kms: "ARN+role_arn" at rule level with optional aws_profile
      kmsArnWithRole =
        if kmsEnabled then
          let
            arn = kmsConfig.keyArn;
            role = kmsConfig.roleArn or "";
          in
          if role != "" then "${arn}+${role}" else arn
        else
          "";
      kmsEntry =
        if !kmsEnabled then
          [ ]
        else
          [ "    kms: ${builtins.toJSON kmsArnWithRole}" ]
          ++ lib.optional (
            kmsConfig.awsProfile or "" != ""
          ) "    aws_profile: ${builtins.toJSON kmsConfig.awsProfile}";
    in
    if names == [ ] && !kmsEnabled then
      [ ]
    else
      [
        "  - path_regex: ${pathRegex}"
        "    unencrypted_comment_regex: ${builtins.toJSON unencryptedCommentRegex}"
      ]
      ++ ageLines
      ++ kmsEntry;

  sopsConfigText =
    let
      # Default: treat every comment as plaintext metadata. Comments next to
      # values in `.sops.yaml` files double as descriptions in the studio UI
      # and must therefore remain unencrypted.
      defaultUnencryptedCommentRegex = ".*";

      explicitRuleStrings = lib.concatMap (
        rule:
        mkRuleLines rule.path-regex (expandRuleRecipients rule) (
          rule.unencrypted-comment-regex or defaultUnencryptedCommentRegex
        )
        ++ [ "" ]
      ) creationRulesConfig;

      legacyRuleStrings = lib.concatMap (
        file:
        mkRuleLines "^${file}$" secretFilesByGroup.${file} defaultUnencryptedCommentRegex ++ [ "" ]
      ) (lib.sort lib.lessThan (lib.attrNames secretFilesByGroup));

      defaultRuleStrings = mkRuleLines ".*" recipientNames defaultUnencryptedCommentRegex ++ [ "" ];

      nonEmptyExplicitRuleStrings = lib.filter (line: line != "") explicitRuleStrings;

      nonEmptyLegacyRuleStrings = lib.filter (line: line != "") legacyRuleStrings;

      ruleStrings =
        if nonEmptyExplicitRuleStrings != [ ] then
          explicitRuleStrings ++ defaultRuleStrings
        else if nonEmptyLegacyRuleStrings != [ ] then
          legacyRuleStrings
        else
          defaultRuleStrings;
    in
    if (recipientNames == [ ] && !kmsEnabled) || ruleStrings == [ ] then
      ''
        # Auto-generated from stackpanel secrets config - DO NOT EDIT.
        # Configure recipients and creation rules to populate this file.
        keys: []
        creation_rules: []
      ''
    else
      ''
        # Auto-generated from stackpanel secrets config - DO NOT EDIT.
        # All YAML comments inside encrypted files are stored in plaintext and
        # double as descriptions in the studio UI.
        keys:${if recipientNames == [ ] then " []" else ""}
        ${lib.optionalString (recipientNames != [ ]) (
          lib.concatMapStringsSep "\n" (
            name:
            "  - &${normalizeAnchor name} ${normalizeRecipientPublicKey recipientsConfig.${name}.public-key}"
          ) recipientNames
        )}
        creation_rules:
        ${lib.concatStringsSep "\n" ruleStrings}
      '';

  legacySecretsCleanupScript = ''
    ${cfgLib.bashLib}

    SECRETS_DIR=${cfgLib.getWithDefault "secrets.secrets-dir" cfg.secrets-dir}

    rm -f "$SECRETS_DIR/groups.sops.yaml"
    rm -f "$SECRETS_DIR/groups.json"
    rm -f "$SECRETS_DIR/apps.json"
    rm -f "$SECRETS_DIR/bin/add-recipient.sh"
    rm -f "$SECRETS_DIR/vars/.sops.yaml"
    rm -rf "$SECRETS_DIR/recipients"
  '';

  rekeyScriptText = ''
    #!/usr/bin/env bash
    set -euo pipefail

    SCRIPT_DIR="$(cd "$(dirname "''${BASH_SOURCE[0]}")" && pwd)"
    SECRETS_DIR="$(dirname "$SCRIPT_DIR")"
    VARS_DIR="$SECRETS_DIR/vars"
    FILTER="''${1:-}"
    REKEY_COUNT=0

    if [[ ! -d "$VARS_DIR" ]]; then
      echo "No vars directory found at $VARS_DIR"
      exit 0
    fi

    shopt -s nullglob
    for file in "$VARS_DIR"/*.sops.yaml; do
      [[ -f "$file" ]] || continue
      group="$(basename "$file" .sops.yaml)"
      if [[ -n "$FILTER" && "$group" != "$FILTER" ]]; then
        continue
      fi

      if sops updatekeys --yes "$file" >/dev/null; then
        echo "  $(basename "$file"): updated"
        REKEY_COUNT=$((REKEY_COUNT + 1))
      else
        echo "  $(basename "$file"): FAILED" >&2
        exit 1
      fi
    done

    echo ""
    echo "Updated keys for $REKEY_COUNT secret file(s)"
  '';

  manifestJson = builtins.toJSON {
    variables = lib.mapAttrs (_: meta: {
      file = meta.file;
      yamlKey = meta.yamlKey;
      tags = meta.tags;
      recipients = meta.recipients;
    }) secretFilesMeta;
  };
in
{
  inherit
    cfg
    projectRoot
    variablesBackend
    isChamber
    chamberCfg
    cfgLib
    secretsLib
    recipientNames
    recipientsConfig
    normalizedRecipientPubkeys
    recipientGroupsConfig
    creationRulesConfig
    sopsAgeSources
    sopsAgeSourceLines
    sopsAgeKeyPaths
    sopsAgeKeyOpRefs
    sopsKeyservices
    normalizeVariableId
    getVarName
    getKeyGroup
    secretFileStem
    secretYamlKey
    normalizeAnchor
    masterKeysConfig
    appLinkTagsByVariable
    secretVariables
    secretIds
    secretFilesMeta
    secretTags
    secretRecipients
    sopsConfigText
    legacySecretsCleanupScript
    rekeyScriptText
    expandRuleRecipients
    manifestJson
    ;
}
