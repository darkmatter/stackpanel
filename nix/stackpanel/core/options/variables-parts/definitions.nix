{
  lib,
  config,
}:
let
  cfg = config.stackpanel;

  # Secrets directory relative to project root
  secretsDir = cfg.secrets.secrets-dir or ".stack/secrets";

  # Extract keygroup from variable ID.
  # "/secret/postgres-url" -> "secret"
  # "/dev/postgres-url" -> "dev"
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

  # Variable submodule: user-facing id/value plus read-only derived metadata.
  variableModule =
    { config, name, ... }:
    {
      options = {
        id = lib.mkOption {
          type = lib.types.str;
          default = name;
          description = ''
            Canonical variable identifier. Use a leading slash followed by either
            a writable scope (`/<scope>/<name>`) or the read-only computed namespace
            (`/computed/<source>/<path>`).

            This defaults to the attribute key, so it normally does not need to
            be written in config files.

            Writable scopes are storage groups. Every non-computed variable is
            stored in the SOPS file for its first path segment:
              `/secret/postgres-url` -> `.stack/secrets/vars/secret.sops.yaml` (key: `postgres_url`)
              `/dev/postgres-url`    -> `.stack/secrets/vars/dev.sops.yaml` (key: `postgres_url`)
              `/test/api-url`        -> `.stack/secrets/vars/test.sops.yaml` (key: `api_url`)

            `/computed/*` is reserved for module-produced values. These are
            materialized into the variable graph for env/codegen consumers, but
            are not written to SOPS:
              `/computed/apps/web/port`
              `/computed/apps/web/url`
              `/computed/services/postgres/port`
          '';
          example = "/dev/DATABASE_URL";
        };

        value = lib.mkOption {
          type = lib.types.str;
          default = "";
          apply = value: if !(isComputed name) && value == "" then "var://${name}" else value;
          description = ''
            The value of this variable.

            For writable scoped variables, leave this empty in Nix. Empty values
            default to `var://<id>`, a variable-link marker used by codegen/runtime
            resolution; the encrypted `vars/<scope>.sops.yaml` file remains the
            source of truth.

            For computed (`/computed/*`) variables, modules set this to the computed
            Nix value, such as a port or URL.

            Legacy: ref+sops:// values are still supported during migration.
          '';
          example = "var:///dev/DATABASE_URL";
        };

        # Computed attributes (read-only)
        keyGroup = lib.mkOption {
          type = lib.types.str;
          readOnly = true;
          description = ''
            First path segment extracted from `id`. For writable variables this is
            the storage scope/SOPS group, such as `secret`, `dev`, `staging`, `prod`,
            or `test`. For `/computed/*`, this is `computed`.
          '';
          example = "dev";
        };

        varName = lib.mkOption {
          type = lib.types.str;
          readOnly = true;
          description = ''
            Final path segment extracted from `id`. This is the env-style variable
            name shown to consumers and normalized into `secretYamlKey` for SOPS.
          '';
          example = "DATABASE_URL";
        };

        isSecret = lib.mkOption {
          type = lib.types.bool;
          readOnly = true;
          description = ''
            Whether this variable is writable and backed by a grouped SOPS file.
            True for every non-`/computed/*` id.
          '';
          example = true;
        };

        isComputed = lib.mkOption {
          type = lib.types.bool;
          readOnly = true;
          description = ''
            Whether this variable lives under `/computed/*`. Computed variables are
            read-only outputs contributed by Stackpanel modules, not user-managed
            secret inputs.
          '';
          example = false;
        };

        isValsRef = lib.mkOption {
          type = lib.types.bool;
          readOnly = true;
          description = ''
            Whether `value` is a legacy vals reference. Currently false for new
            variable entries; `ref+sops://...` values remain accepted as migration
            input.
          '';
          example = false;
        };

        sopsFile = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          readOnly = true;
          description = ''
            Project-relative path to this variable's grouped SOPS file, derived from
            `stackpanel.secrets.secrets-dir` and `keyGroup`. Null for `/computed/*`.
          '';
          example = ".stack/secrets/vars/dev.sops.yaml";
        };

        secretYamlKey = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          readOnly = true;
          description = ''
            Deterministic YAML key used inside `sopsFile`. Derived from `varName` by
            normalizing separators such as `-`, `.`, `/`, and spaces to `_`.
          '';
          example = "DATABASE_URL";
        };

        isPlaintext = lib.mkOption {
          type = lib.types.bool;
          readOnly = true;
          description = ''
            Whether this value is stored directly in evaluated Nix config instead of
            a grouped SOPS file. This is true only for `/computed/*` outputs.
          '';
          example = false;
        };
      };

      config =
        let
          keyGroup = getKeyGroup config.id;
          usesSops = !(isComputed config.id);
        in
        {
          inherit keyGroup;
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
    Workspace variable registry keyed by full variable ID.

    ID prefixes determine ownership and storage:
      `/computed/*`  - read-only values produced by Nix modules
      `/<scope>/*`   - writable, grouped variables stored in `vars/<scope>.sops.yaml`

    Common writable scopes are `/dev/*`, `/staging/*`, `/prod/*`, `/test/*`, and
    `/secret/*`, but scopes are just storage groups. Non-computed values resolve
    to `var://<id>` markers by default; the grouped SOPS file is the source of
    truth. Use SOPS creation rules such as
    `^\.stack/secrets/vars/dev\.sops\.yaml$` to control recipients per scope.

    Computed ids are reserved for Stackpanel modules. Examples include app ports,
    app URLs, and service ports published as `/computed/apps/web/port`,
    `/computed/apps/web/url`, and `/computed/services/postgres/port`.
  '';

  example = lib.literalExpression ''
    {
      # Shared secret scope. Value lives in vars/secret.sops.yaml under key DATABASE_URL.
      "/secret/DATABASE_URL" = { };

      # Env-scoped groups. Same var name can differ per environment.
      "/dev/STRIPE_WEBHOOK_SECRET" = { };
      "/prod/STRIPE_WEBHOOK_SECRET" = { };

      # Explicit value is allowed, but most writable variables should stay empty
      # so they resolve through the encrypted scope file.
      "/test/API_BASE_URL" = { value = "http://localhost:3000"; };

      # Existing vals refs are accepted during migration.
      "/legacy/SMTP_PASSWORD" = { value = "ref+sops://legacy/smtp-password"; };

      # Computed variables are usually contributed by modules, not handwritten.
      "/computed/apps/web/port" = { value = "3000"; };
      "/computed/apps/web/url" = { value = "https://web.localhost"; };
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
