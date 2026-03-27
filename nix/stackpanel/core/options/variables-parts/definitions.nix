{
  lib,
  config,
}:
let
  cfg = config.stackpanel;

  # Secrets directory relative to project root
  secretsDir = cfg.secrets.secrets-dir or ".stack/secrets";

  # Extract keygroup from variable ID
  # "/secret/postgres-url" -> "secret"
  # "/computed/apps/web/port" -> "computed"
  getKeyGroup =
    id:
    let
      cleaned = lib.removePrefix "/" id;
      parts = lib.splitString "/" cleaned;
    in
    if parts != [ ] then builtins.head parts else "dev";

  # Extract variable name from ID (last path component)
  # "/dev/DATABASE_URL" -> "DATABASE_URL"
  getVarName =
    id:
    let
      cleaned = lib.removePrefix "/" id;
      parts = lib.splitString "/" cleaned;
    in
    if parts != [ ] then lib.last parts else id;

  # Check if a variable ID is computed (read-only)
  isComputed = id: lib.hasPrefix "/computed/" id;

  secretFileStem =
    id:
    let
      raw = getVarName id;
      sanitized = builtins.replaceStrings [ "/" "\\\\" " " ] [ "-" "-" "-" ] raw;
    in
    sanitized;

  secretYamlKey =
    id:
    let
      raw = getVarName id;
      normalized = builtins.replaceStrings [ "-" "." "/" " " ] [ "_" "_" "_" "_" ] raw;
    in
    normalized;

  # Variable submodule - just id and value, with computed helpers
  variableModule =
    { config, name, ... }:
    {
      options = {
        id = lib.mkOption {
          type = lib.types.str;
          default = name;
          description = ''
            Variable identifier. Format: /<scope>/<NAME>

            This defaults to the attribute key, so it normally does not need to
            be written in config files.

            Variables are stored in group-based SOPS files by prefix:
              /secret/postgres-url -> .stack/secrets/vars/secret.sops.yaml (key: postgres_url)
              /dev/postgres-url    -> .stack/secrets/vars/dev.sops.yaml (key: postgres_url)
              /test/api-url        -> .stack/secrets/vars/test.sops.yaml (key: api_url)

            Computed variables use /computed/<source>/<path>:
              /computed/apps/web/port
              /computed/services/postgres/port
          '';
        };

        value = lib.mkOption {
          type = lib.types.str;
          default = "";
          apply = value: if !(isComputed name) && value == "" then "var://${name}" else value;
          description = ''
            The value of this variable.

            For non-computed variables: a variable link marker used by codegen/runtime resolution.
            For computed (/computed/*): the computed value from Nix.

            Legacy: ref+sops:// values are still supported during migration.
          '';
        };

        # Computed attributes (read-only)
        keyGroup = lib.mkOption {
          type = lib.types.str;
          readOnly = true;
          description = "Key group extracted from ID (e.g., 'secret', 'dev', 'test', 'computed')";
        };

        varName = lib.mkOption {
          type = lib.types.str;
          readOnly = true;
          description = "Variable name extracted from ID (last path component)";
        };

        isSecret = lib.mkOption {
          type = lib.types.bool;
          readOnly = true;
          description = "Whether this variable is backed by a grouped SOPS file";
        };

        isComputed = lib.mkOption {
          type = lib.types.bool;
          readOnly = true;
          description = "Whether this is a computed (read-only) variable";
        };

        isValsRef = lib.mkOption {
          type = lib.types.bool;
          readOnly = true;
          description = "Whether the value is a vals reference";
        };

        sopsFile = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          readOnly = true;
          description = "Path to the SOPS file for this variable's group (null for /computed/*)";
        };

        secretYamlKey = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          readOnly = true;
          description = "Deterministic YAML key used inside the group SOPS file";
        };

        isPlaintext = lib.mkOption {
          type = lib.types.bool;
          readOnly = true;
          description = "Whether this variable is stored directly in config instead of a SOPS group";
        };
      };

      config =
        let
          keyGroup = getKeyGroup config.id;
          usesSops = !(isComputed config.id);
        in
        {
          keyGroup = keyGroup;
          varName = getVarName config.id;
          isSecret = usesSops;
          isComputed = isComputed config.id;
          isValsRef = false;
          isPlaintext = !usesSops;
          sopsFile = if usesSops then "${secretsDir}/vars/${keyGroup}.sops.yaml" else null;
          secretYamlKey = if usesSops then secretYamlKey config.id else null;
        };
    };

  description = ''
     Workspace variables keyed by their full variable ID.

    Prefixes determine storage:
      /computed/* - Nix-computed values (read-only)
      /*         - Grouped SOPS-backed variables stored in `vars/<prefix>.sops.yaml`

    Non-computed variable values resolve to variable-link markers; the group SOPS file is the source of truth.
  '';

  example = lib.literalExpression ''
    {
      # Shared config (plaintext, NOT encrypted)
       "/var/LOG_LEVEL" = { value = "info"; };
       "/var/API_VERSION" = { value = "v1"; };

      # Grouped variable (value lives in vars/secret.sops.yaml under key postgres_url)
       "/secret/postgres-url" = { value = ""; };

      # Env-scoped grouped variable (value lives in vars/dev.sops.yaml under key postgres_url)
       "/dev/postgres-url" = { value = ""; };
     }
  '';
in
{
  inherit
    getKeyGroup
    getVarName
    isComputed
    secretFileStem
    secretYamlKey
    variableModule
    description
    example
    ;
}
