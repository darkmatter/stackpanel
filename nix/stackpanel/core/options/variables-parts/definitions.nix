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

            Secret variables use a flat namespace:
              /secret/postgres-url -> .stack/secrets/vars/postgres-url.sops.yaml

            Computed variables use /computed/<source>/<path>:
              /computed/apps/web/port
              /computed/services/postgres/port
          '';
        };

        value = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = ''
            The value of this variable.

            For plaintext variables (/var/*): the literal value.
            For secrets (/secret/*): empty string (SOPS file is source of truth).
            For computed (/computed/*): the computed value from Nix.

            Legacy: ref+sops:// values are still supported during migration.
          '';
        };

        # Computed attributes (read-only)
        keyGroup = lib.mkOption {
          type = lib.types.str;
          readOnly = true;
          description = "Key group extracted from ID (e.g., 'secret', 'var', 'computed')";
        };

        varName = lib.mkOption {
          type = lib.types.str;
          readOnly = true;
          description = "Variable name extracted from ID (last path component)";
        };

        isSecret = lib.mkOption {
          type = lib.types.bool;
          readOnly = true;
          description = "Whether this is a SOPS-encrypted secret";
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
          description = "Path to the SOPS file for this keygroup (null for /var/* and /computed/*)";
        };

        secretYamlKey = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          readOnly = true;
          description = "Deterministic YAML key used inside the per-variable SOPS file";
        };

        isPlaintext = lib.mkOption {
          type = lib.types.bool;
          readOnly = true;
          description = "Whether this is a plaintext config variable (/var/*)";
        };
      };

      config =
        let
          keyGroup = getKeyGroup config.id;
          usesSops = keyGroup == "secret";
        in
        {
          keyGroup = keyGroup;
          varName = getVarName config.id;
          isSecret = usesSops;
          isComputed = isComputed config.id;
          isValsRef = false;
          isPlaintext = keyGroup == "var";
          sopsFile = if usesSops then "${secretsDir}/vars/${secretFileStem config.id}.sops.yaml" else null;
          secretYamlKey = if usesSops then secretYamlKey config.id else null;
        };
    };

  description = ''
     Workspace variables keyed by their full variable ID.

    Prefixes determine storage:
      /var/*      - Shared config (plaintext, NOT encrypted)
      /secret/*   - Flat secrets (one SOPS file per variable)
      /computed/* - Nix-computed values (read-only)

    Secret variable values are empty strings; the SOPS file is the source of truth.
    Plaintext variables store their value directly.
  '';

  example = lib.literalExpression ''
    {
      # Shared config (plaintext, NOT encrypted)
       "/var/LOG_LEVEL" = { value = "info"; };
       "/var/API_VERSION" = { value = "v1"; };

      # Secret (value lives in vars/postgres-url.sops.yaml)
       "/secret/postgres-url" = { value = ""; };
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
