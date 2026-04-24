# ==============================================================================
# env-package.nix
#
# Generates the @gen/env package directly in the target package directory.
#
# This codegen is driven entirely by `stackpanel.apps.<app>.env`, which maps
# each environment variable name to an `EnvironmentVariable` (see
# `nix/stackpanel/db/schemas/apps.proto.nix`):
#
#   stackpanel.apps.web.env = {
#     PORT          = { value = "3000"; };
#     DATABASE_URL  = { secret = true; sops = "/dev/database-url"; };
#     LOG_LEVEL     = { defaultValue = "info"; };
#   };
#
# A `sops` field of the form `/<group>/<name>` resolves to:
#   - file: <secrets-dir>/vars/<group>.sops.yaml
#   - key:  snake_case form of <name> (hyphens become underscores)
#
# Generated structure:
#   packageDir/
#     package.json
#     tsconfig.json
#     README.md
#     src/
#       embedded-data.ts        — runtime metadata (ENVIRONMENT_VARIABLES)
#       index.ts                — barrel re-export of all per-app modules
#       exports/<app>.ts        — typed env accessor for each app
#       runtime/
#         loader.ts             — generic env loader runtime
#         node-loader.ts        — Node-specific entrypoint
#         docker-entrypoint.ts  — Docker entrypoint helper
#         generated-payloads/registry.ts — payload registry stub
#   .stack/gen/codegen/env-manifest.json — Go consumer manifest
# ==============================================================================
{
  lib,
  config,
  ...
}:
let
  cfg = config.stackpanel;
  apps = cfg.apps or { };
  users = cfg.users or { };
  secretsCfg = cfg.secrets or { };
  explicitRecipients = secretsCfg.recipients or { };
  packageName = cfg.env.package-name or "@gen/env";

  # Default environments when an app does not declare `environmentIds`.
  defaultEnvironments = [
    "dev"
    "prod"
    "staging"
    "test"
  ];

  # Runtime aliases (mirrors `normalizeRuntimeEnv` in runtime/loader.ts).
  # Used so a recipient tagged `production` still matches an app env `prod`.
  envAliases = env:
    if env == "prod" then [ "prod" "production" ]
    else if env == "dev" then [ "dev" "development" ]
    else [ env ];

  # Normalize whatever the user wrote in `app.environmentIds` to the canonical
  # short form used on disk and at runtime.
  normalizeEnvName = env:
    if env == "production" then "prod"
    else if env == "development" then "dev"
    else env;

  # Output paths (all relative to project root)
  packageDir = cfg.env.output-dir or "packages/gen/env";
  generatedDir = "${packageDir}/src";
  exportsDir = "${generatedDir}/exports";
  runtimeDir = "${generatedDir}/runtime";
  payloadRuntimeDir = "${runtimeDir}/generated-payloads";
  secretsDir = secretsCfg.secrets-dir or ".stack/secrets";

  # ===========================================================================
  # Templates
  # ===========================================================================
  templateDir = ./templates/env;
  templates = {
    barrel = builtins.readFile "${templateDir}/barrel.tmpl.ts";
    envExportMeta = builtins.readFile "${templateDir}/env-export-meta.tmpl.ts";
    loader = builtins.readFile "${templateDir}/loader.ts";
    nodeLoader = builtins.readFile "${templateDir}/node-loader.ts";
    payloadRegistry = builtins.readFile "${templateDir}/payload-registry.ts";
    dockerEntrypoint = builtins.readFile "${templateDir}/docker-entrypoint.ts";
    readme = builtins.readFile "${templateDir}/README.tmpl.md";
  };

  # ===========================================================================
  # Helpers
  # ===========================================================================

  # Convert kebab-case package/app names to a JS identifier.
  #   "stackpanel-go" -> "stackpanelGo"
  toJsIdentifier =
    name:
    let
      parts = lib.splitString "-" name;
      capitalize = s: lib.toUpper (lib.substring 0 1 s) + lib.substring 1 (-1) s;
      first = lib.head parts;
      rest = map capitalize (lib.tail parts);
    in
    lib.concatStrings ([ first ] ++ rest);

  # ---------------------------------------------------------------------------
  # SOPS reference resolution
  #
  # `sops = "/group/name"` resolves to:
  #   - file: <secrets-dir>/vars/<group>.sops.yaml
  #   - key:  snake_case of <name> (final path segment)
  #
  # Hyphens, dots, and spaces in the final segment become underscores so the
  # YAML key matches conventional snake_case used inside SOPS files.
  # ---------------------------------------------------------------------------
  sopsRefParts =
    sopsPath:
    let
      cleaned = lib.removePrefix "/" sopsPath;
      parts = lib.splitString "/" cleaned;
      group = if parts != [ ] then builtins.head parts else "shared";
      lastSegment = if parts != [ ] then lib.last parts else cleaned;
      key = builtins.replaceStrings [ "-" "." " " ] [ "_" "_" "_" ] lastSegment;
    in
    {
      inherit group key;
      file = "${secretsDir}/vars/${group}.sops.yaml";
    };

  resolveSopsEntry =
    sopsPath:
    let
      parts = sopsRefParts sopsPath;
    in
    {
      kind = "sopsRef";
      path = parts.file;
      fileType = "yaml";
      key = parts.key;
    };

  # ---------------------------------------------------------------------------
  # Per-app env normalisation
  #
  # Returns the resolved env attrset for a given app, where each value is an
  # `EnvironmentVariable` submodule. We always default missing optional fields
  # to safe values so downstream codegen never has to second-guess.
  # ---------------------------------------------------------------------------
  normalizeEnvVar =
    envKey: rawVar:
    let
      value = rawVar.value or null;
      sops = rawVar.sops or null;
      defaultValue = rawVar.defaultValue or null;
      description = rawVar.description or null;
      hasValue = value != null && value != "";
      hasSops = sops != null && sops != "";
      hasDefault = defaultValue != null && defaultValue != "";
      hasDescription = description != null && description != "";
    in
    {
      key = if (rawVar.key or "") != "" then rawVar.key else envKey;
      required = rawVar.required or false;
      # A SOPS reference always implies a sensitive value.
      secret = (rawVar.secret or false) || hasSops;
      value = if hasValue then value else null;
      sops = if hasSops then sops else null;
      defaultValue = if hasDefault then defaultValue else null;
      description = if hasDescription then description else null;
    };

  getAppEnv =
    appCfg:
    let
      raw = appCfg.env or { };
    in
    lib.mapAttrs normalizeEnvVar raw;

  # ---------------------------------------------------------------------------
  # Apps that should produce a generated env export.
  # ---------------------------------------------------------------------------
  appsWithEnv = lib.filter (
    appName: (getAppEnv apps.${appName}) != { }
  ) (lib.attrNames apps);

  appPathFor =
    appName:
    let
      rawPath = apps.${appName}.path or appName;
      trimmedDot = lib.removePrefix "./" rawPath;
      trimmedPath =
        if trimmedDot != "" && lib.hasSuffix "/" trimmedDot then
          lib.substring 0 ((builtins.stringLength trimmedDot) - 1) trimmedDot
        else
          trimmedDot;
    in
    if trimmedPath != "" then trimmedPath else appName;

  scopedRootEnvName = appName: env: "${appPathFor appName}/${env}";

  # ---------------------------------------------------------------------------
  # "Loader-guaranteed" predicate: a key is treated as always-present in the
  # generated TypeScript `Env` type when the runtime loader can produce a value
  # without the caller supplying anything. That covers the obvious cases —
  # marked `required`, has a literal `value`, has a `defaultValue`, or is
  # backed by `sops` — and also acts as the rule for whether `validate(input)`
  # needs to enforce its presence (only `required` does, defaults are applied).
  # ---------------------------------------------------------------------------
  isLoaderGuaranteed =
    meta:
    meta.required
    || meta.value != null
    || meta.defaultValue != null
    || meta.sops != null;

  # ---------------------------------------------------------------------------
  # App-scoped root env registry derived from `apps.<app>.env`.
  #
  # Each app contributes one entry per environment ID, keyed by the app path
  # plus environment name (for example `apps/web/dev`). This avoids collisions
  # when multiple apps target the same environment with different values like
  # `PORT`, while still publishing the same env variable submodule shape as
  # `options.stackpanel.envs.<scope>.<KEY>`.
  # ---------------------------------------------------------------------------
  mergedAppEnvs = lib.listToAttrs (
    lib.concatMap (
      appName:
      let
        envIds = appEnvironmentIds appName;
        envVars = getAppEnv apps.${appName};
      in
      map (env: {
        name = scopedRootEnvName appName env;
        value = envVars;
      }) envIds
    ) appsWithEnv
  );

  # All envs known to the system. The env-codegen module publishes
  # `mergedAppEnvs` to `config.stackpanel.envs`, and other modules can layer
  # additional `stackpanel.envs.<scope>.<KEY>` declarations on top — so
  # `cfg.envs` is the full fix-point once the module system has resolved.
  rootEnvs = cfg.envs or { };

  rootEnvNames = lib.attrNames rootEnvs;

  # ===========================================================================
  # Manifest construction
  # ===========================================================================

  # Per-app metadata used by both the runtime (`embedded-data.ts`) and the Go
  # codegen consumer.
  appEnvVarsMeta = lib.listToAttrs (
    map (appName: {
      name = appName;
      value = lib.mapAttrs (
        _envKey: meta: {
          inherit (meta) key required secret defaultValue description;
          # Echo the SOPS path so the runtime error message can tell the user
          # exactly where to add the missing secret.
          sops = meta.sops;
        }
      ) (getAppEnv apps.${appName});
    }) appsWithEnv
  );

  # Cross-cutting (non-app) root env scopes — entries in `cfg.envs` keyed by
  # a bare name like `deploy` rather than `apps/<app>/<env>`. These are the
  # scopes the runtime exposes via `loadEnvScope("deploy")` and that modules
  # contribute to via `config.stackpanel.envs.<scope>.<KEY> = { ... };`.
  rootScopeNames = lib.filter (name: ! lib.hasPrefix "apps/" name) rootEnvNames;

  # Same shape as `appEnvVarsMeta` but keyed by root scope name. Surfaced in
  # the generated `embedded-data.ts` as `ROOT_ENV_VARIABLES` so the runtime
  # `checkRequiredEnv` can validate root-scope payloads, and consumed by the
  # Go codegen pipeline so MOTD / studio warnings cover deploy-time vars too.
  rootScopeVarsMeta = lib.listToAttrs (
    map (scope: {
      name = scope;
      value = lib.mapAttrs (
        _envKey: rawVar:
        let meta = normalizeEnvVar _envKey rawVar; in
        {
          inherit (meta) key required secret defaultValue description sops;
        }
      ) (rootEnvs.${scope} or { });
    }) rootScopeNames
  );

  # Build the var resolution entries for the Go codegen pipeline.
  mkResolutionEntries =
    appName:
    let
      appEnv = getAppEnv apps.${appName};
    in
    lib.mapAttrs (
      _envKey: meta:
      if meta.sops != null then
        resolveSopsEntry meta.sops
      else if meta.value != null then
        {
          kind = "literal";
          value = meta.value;
        }
      else if meta.defaultValue != null then
        {
          kind = "literal";
          value = meta.defaultValue;
        }
      else
        {
          kind = "literal";
          value = "";
        }
    ) appEnv;

  # ---------------------------------------------------------------------------
  # Recipient resolution
  #
  # Two sources of recipients are merged:
  #   1. `stackpanel.users.<name>.public-keys` — each public key becomes a
  #      recipient tagged with the user's `secrets-allowed-environments`.
  #      Multiple keys per user are disambiguated with a `_2`, `_3` suffix.
  #   2. `stackpanel.secrets.recipients` — explicit `{ public-key; tags; }`
  #      entries, useful for service accounts (CI, keyservice, …).
  #
  # For every (app, env) target we build a tag set:
  #   [ env, normalize(env), <env aliases…>, "<app>/<env>", "<app>/<alias>" ]
  # and select recipients whose own tags intersect that set. Empty-tag
  # recipients are not treated as catch-alls — to participate in any payload
  # a recipient must opt in via tags.
  # ---------------------------------------------------------------------------

  # Recipients derived from `stackpanel.users.*`. Each user's public keys are
  # exploded into individual recipient entries with deterministic names.
  userRecipients = lib.foldl' lib.recursiveUpdate { } (
    lib.mapAttrsToList (
      userName: user:
      let
        keys = user.public-keys or [ ];
        tags = user.secrets-allowed-environments or [ ];
        mkRecipientName = i: if i == 0 then userName else "${userName}_${toString (i + 1)}";
      in
      lib.listToAttrs (
        lib.imap0 (i: publicKey: {
          name = mkRecipientName i;
          value = {
            public-key = publicKey;
            inherit tags;
          };
        }) keys
      )
    ) users
  );

  # Final recipient registry. Explicit `secrets.recipients` entries override
  # user-derived recipients of the same name (matches behaviour in
  # `nix/stackpanel/secrets/default-parts/context.nix`).
  recipientRegistry = userRecipients // explicitRecipients;

  recipientTagsFor = name: (recipientRegistry.${name}.tags or [ ]);
  recipientPublicKey = name: (recipientRegistry.${name}.public-key or null);

  # Build the candidate tag set for a (app, env) pair so recipient filtering
  # can match any of the equivalent forms used across the configuration.
  targetTagsFor = appName: env:
    let
      aliases = envAliases env;
      composites = map (a: "${appName}/${a}") aliases;
    in
    lib.unique (aliases ++ composites);

  selectRecipientsFor = appName: env:
    let
      wanted = targetTagsFor appName env;
      matches = name:
        let userTags = recipientTagsFor name; in
        userTags != [ ] && lib.any (t: lib.elem t wanted) userTags;
      names = lib.filter matches (lib.attrNames recipientRegistry);
      keys = lib.filter (k: k != null && k != "") (map recipientPublicKey names);
    in
    lib.unique keys;

  # ---------------------------------------------------------------------------
  # Per-app environment fan-out
  # ---------------------------------------------------------------------------
  appEnvironmentIds = appName:
    let
      raw = apps.${appName}.environmentIds or [ ];
      normalized = map normalizeEnvName raw;
    in
    lib.unique (if normalized == [ ] then defaultEnvironments else normalized);

  # Targets are dropped when no recipient is eligible — the Go codegen would
  # otherwise fail with "no recipients configured". A buildable but partial
  # set of targets is preferable to a hard failure for an unrelated env.
  appEnvironmentTargets = appName:
    let
      envs = appEnvironmentIds appName;
      vars = mkResolutionEntries appName;
    in
    lib.filter (t: t.recipients != [ ]) (
      map (env: {
        app = appName;
        environment = env;
        outputPath = "${packageDir}/data/${env}/${appName}.sops.json";
        recipients = selectRecipientsFor appName env;
        inherit vars;
      }) envs
    );

  # ---------------------------------------------------------------------------
  # Root-level env targets
  #
  # Every environment surfaced by `rootEnvs` (apps + module-contributed) gets
  # one SOPS payload at `<packageDir>/data/_envs/<env>.sops.json`. The Go
  # codegen pipeline treats `_envs` as a synthetic "app" so the existing
  # SOPS encryption + payload writer is reused; no TypeScript loader is
  # emitted for these targets yet (manifest-only scaffolding).
  # ---------------------------------------------------------------------------
  rootEnvResolutionEntries =
    envName:
    let
      vars = rootEnvs.${envName} or { };
    in
    lib.mapAttrs (
      _envKey: meta:
      if meta.sops != null then
        resolveSopsEntry meta.sops
      else if meta.value != null then
        {
          kind = "literal";
          value = meta.value;
        }
      else if meta.defaultValue != null then
        {
          kind = "literal";
          value = meta.defaultValue;
        }
      else
        {
          kind = "literal";
          value = "";
        }
    ) vars;

  parseScopedRootEnvName =
    envName:
    let
      matchingApps = lib.filter (
        appName: lib.hasPrefix "${appPathFor appName}/" envName
      ) appsWithEnv;
      sortedMatches = lib.sort (
        a: b: builtins.stringLength (appPathFor a) > builtins.stringLength (appPathFor b)
      ) matchingApps;
    in
    if sortedMatches == [ ] then
      null
    else
      let
        appName = lib.head sortedMatches;
        prefix = "${appPathFor appName}/";
      in
      {
        inherit appName;
        env = lib.removePrefix prefix envName;
      };

  # Recipient resolution for root env scopes.
  #
  # Two regimes:
  #
  #   - App-scoped names (`apps/<app>/<env>`) are auto-populated from
  #     `apps.<app>.env` by `mergedAppEnvs`. They get the same recipients as
  #     the matching per-app payload so the SOPS file ends up encrypted to
  #     the same set of keys as `data/<env>/<app>.sops.json`. (See note on
  #     `rootScopeNames` below — these never reach `rootEnvTargets` anymore;
  #     they're intentionally redundant duplicates that we don't write.)
  #
  #   - Bare cross-cutting scopes (`deploy`, `infra`, `ci`, …) are not tied
  #     to a single app or env. They hold deploy-time / project-wide secrets
  #     used by `loadEnvScope("<scope>")` from deploy entrypoints. Defaulting
  #     these to "no recipients" silently drops the payload and breaks the
  #     runtime — which is exactly the bug the fallback below fixes.
  #
  #     The natural reader of a bare scope is "anyone who can ship to prod",
  #     because deploy-time credentials are by definition production
  #     credentials. So in addition to recipients explicitly tagged with the
  #     scope name (e.g. `tags = [ "deploy" ]` for fine-grained control), we
  #     also include anyone tagged with `prod`/`production`.
  rootEnvRecipients =
    envName:
    let
      scoped = parseScopedRootEnvName envName;
    in
    if scoped != null then
      selectRecipientsFor scoped.appName scoped.env
    else
      let
        # Tags that grant read access to this bare scope:
        #   - the scope name itself + its env aliases (opt-in via tags)
        #   - `prod` / `production` (default: deploy = prod credentials)
        scopeTags = envAliases envName;
        prodTags = [ "prod" "production" ];
        wanted = lib.unique (scopeTags ++ prodTags);
        matches = name:
          let userTags = recipientTagsFor name; in
          userTags != [ ] && lib.any (t: lib.elem t wanted) userTags;
        names = lib.filter matches (lib.attrNames recipientRegistry);
        keys = lib.filter (k: k != null && k != "") (map recipientPublicKey names);
      in
      lib.unique keys;

  # Only emit SOPS payloads for bare cross-cutting scopes. App-scoped entries
  # in `cfg.envs` (the `apps/<app>/<env>` keys auto-populated from
  # `mergedAppEnvs`) would otherwise produce duplicate `_envs/apps/<app>/<env>`
  # SOPS files that are byte-equivalent to the per-app payloads at
  # `data/<env>/<app>.sops.json` — wasted codegen, wasted bundle size, and a
  # confusing public surface for `loadEnvScope`. The bare-scope filter
  # (`rootScopeNames`) is the same one used to publish `ROOT_ENV_VARIABLES`,
  # keeping the on-disk layout, the runtime metadata, and the loader API in
  # lockstep.
  rootEnvTargets = lib.filter (t: t.recipients != [ ] && t.vars != { }) (
    map (envName: {
      app = "_envs";
      environment = envName;
      outputPath = "${packageDir}/data/_envs/${envName}.sops.json";
      recipients = rootEnvRecipients envName;
      vars = rootEnvResolutionEntries envName;
    }) rootScopeNames
  );

  envBuildManifest = {
    schemaVersion = 2;
    dataRoot = "${packageDir}/data";
    environmentVariables = appEnvVarsMeta;
    rootScopeVariables = rootScopeVarsMeta;
    targets = (lib.concatMap appEnvironmentTargets appsWithEnv) ++ rootEnvTargets;
  };

  # Map every app to the environments that successfully produced a target.
  # The runtime payload registry only knows about (app, env) pairs that were
  # actually generated, so `AVAILABLE_APP_ENVS` must mirror that set.
  availableAppEnvs = lib.listToAttrs (
    map (appName: {
      name = appName;
      value = lib.unique (map (t: t.environment) (appEnvironmentTargets appName));
    }) appsWithEnv
  );

  embeddedDataModule = ''
    // Auto-generated by Stackpanel — do not edit manually.
    //
    // This module exposes runtime metadata for every environment variable
    // declared via `stackpanel.apps.<app>.env`. The studio UI and any
    // tooling that needs to introspect env shape consumes it directly.

    export const AVAILABLE_APP_ENVS = ${builtins.toJSON availableAppEnvs} as Record<string, string[]>;

    export interface EnvVarMeta {
      key: string;
      required: boolean;
      secret: boolean;
      defaultValue: string | null;
      description: string | null;
      /** SOPS reference of the form `/group/name`, when the variable is
       * sourced from a SOPS file. Used by error messages and the studio
       * UI to point users at the file/key that needs to be set. */
      sops: string | null;
    }

    export const ENVIRONMENT_VARIABLES = ${builtins.toJSON appEnvVarsMeta} as Record<string, Record<string, EnvVarMeta>>;

    /**
     * Cross-cutting root env scopes (anything keyed by a bare name in
     * `stackpanel.envs.<scope>`, as opposed to the auto-populated
     * `apps/<app>/<env>` entries). Surfaces things like the `deploy` scope
     * (`CLOUDFLARE_API_TOKEN`, `NEON_API_KEY`, ...). Used by
     * `loadEnvScope(scope)` and `checkRequiredEnvScope` for validation.
     */
    export const ROOT_ENV_VARIABLES = ${builtins.toJSON rootScopeVarsMeta} as Record<string, Record<string, EnvVarMeta>>;
  '';

  # Type registry consumed by the runtime loaders so `loadEnv("web", env)`
  # returns the typed `Env` shape from `exports/web.ts` rather than a loose
  # `Record<string, string>`. Falls back to `Record<string, string>` for app
  # names that aren't statically known (e.g., values pulled from runtime
  # config), preserving backward compatibility.
  appEnvTypesModule =
    let
      sortedApps = lib.sort (a: b: a < b) appsWithEnv;
      capitalize = s: lib.toUpper (lib.substring 0 1 s) + lib.substring 1 (-1) s;
      pascalCase = name:
        lib.concatStrings (map capitalize (lib.splitString "-" name));
      typeAliasFor = appName: "${pascalCase appName}Env";
      importLines = lib.concatMapStringsSep "\n" (
        appName: "import type { Env as ${typeAliasFor appName} } from \"../exports/${appName}\";"
      ) sortedApps;
      mapEntries = lib.concatMapStringsSep "\n" (
        appName: "  ${builtins.toJSON appName}: ${typeAliasFor appName};"
      ) sortedApps;
      bodyImports = if sortedApps == [ ] then "" else importLines + "\n\n";
      mapBody = if sortedApps == [ ] then "" else "\n" + mapEntries + "\n";
    in
    ''
      // Auto-generated by Stackpanel — do not edit manually.
      // Maps each app declared in `stackpanel.apps.<app>.env` to its typed
      // `Env` shape. The runtime loaders use this so callers get typed
      // results without losing the loose `Record<string, string>` fallback
      // for unknown app names.

      ${bodyImports}export interface AppEnvMap {${mapBody}}

      export type AppName = keyof AppEnvMap;

      // When `App` is a known app key, `EnvFor<App>` is its typed `Env`.
      // Otherwise it falls back to `Record<string, string>` so callers
      // passing an arbitrary `string` (e.g., from runtime config) still
      // type-check.
      export type EnvFor<App extends string> = App extends keyof AppEnvMap
        ? AppEnvMap[App]
        : Record<string, string>;
    '';

  # ===========================================================================
  # TypeScript codegen
  # ===========================================================================

  mkAppEnvExport =
    appName:
    let
      appEnv = getAppEnv apps.${appName};
      sortedKeys = lib.sort (a: b: a < b) (lib.attrNames appEnv);
      # `?` makes the field optional in the emitted TypeScript interface for
      # any key the loader can't guarantee — i.e. nothing about it (no
      # required, no value, no default, no sops) was declared.
      fieldFor =
        key:
        let
          meta = appEnv.${key};
          opt = if isLoaderGuaranteed meta then "" else "?";
        in
        "  ${key}${opt}: string;";
      fields = lib.concatMapStringsSep "\n" fieldFor sortedKeys;
      requiredKeys = lib.filter (k: appEnv.${k}.required) sortedKeys;
      requiredKeysList = lib.concatMapStringsSep ", " (k: builtins.toJSON k) requiredKeys;
      defaultsAttrs = lib.listToAttrs (
        lib.concatMap (
          k:
          let meta = appEnv.${k}; in
          if meta.defaultValue != null then
            [ { name = k; value = meta.defaultValue; } ]
          else
            [ ]
        ) sortedKeys
      );
      defaultsJson = builtins.toJSON defaultsAttrs;
    in
    builtins.replaceStrings
      [ "{{FIELDS}}" "{{REQUIRED_KEYS}}" "{{DEFAULTS}}" ]
      [ fields requiredKeysList defaultsJson ]
      templates.envExportMeta;

  # ---------------------------------------------------------------------------
  # Root index.ts — typed per-app/per-env loader registry.
  #
  #   import { web } from "@gen/env";
  #   const env = await web.dev();
  #   console.log(env.SOME_KEY); // typed against `EnvFor<"web">`
  #
  # Each app exports an object whose keys are the environments declared via
  # `app.environmentIds` (filtered to the set that has eligible recipients,
  # i.e. the same set surfaced in `AVAILABLE_APP_ENVS`). Each value is an
  # async loader that delegates to `loadEnv(<app>, <env>, options)`. The
  # `loadEnv` generic preserves the literal `<app>` so the returned promise
  # is typed as `Promise<EnvFor<"<app>">>` automatically.
  # ---------------------------------------------------------------------------
  mkRootIndexModule =
    let
      sortedApps = lib.sort (a: b: a < b) appsWithEnv;
      mkAppBlock =
        appName:
        let
          jsName = toJsIdentifier appName;
          envs = availableAppEnvs.${appName} or [ ];
          sortedEnvs = lib.sort (a: b: a < b) envs;
          envLines = lib.concatMapStringsSep "\n" (
            env:
            "  ${env}: (options?: LoadEnvOptions) => loadEnv(${builtins.toJSON appName}, ${builtins.toJSON env}, options),"
          ) sortedEnvs;
          body = if sortedEnvs == [ ] then "" else "\n" + envLines + "\n";
        in
        "export const ${jsName} = {${body}} as const;";
      blocks = lib.concatMapStringsSep "\n\n" mkAppBlock sortedApps;
    in
    ''
      // Auto-generated by Stackpanel — do not edit manually.
      //
      // Per-app, per-environment env loaders. Each property is an async
      // function that resolves to the typed `Env` shape declared in
      // `./exports/<app>.ts` (via `EnvFor<"<app>">`).
      //
      //   import { web } from "@gen/env";
      //   const env = await web.dev();
      //   console.log(env.SOME_KEY);
      //
      // For non-Node runtimes (Workers, edge, …) import the no-Node loader
      // directly: `import { loadEnv } from "@gen/env/runtime"` — but note
      // that `@gen/env/runtime` resolves to the Node/Bun loader; portable
      // callers can `import { loadEnv } from "@gen/env/runtime"` with a
      // pre-supplied `secretKey` to avoid the platform layer entirely.
      //
      // To inspect the static `process.env`-backed shape for a single app
      // synchronously, import its per-app module directly:
      //
      //   import { env } from "@gen/env/web";
      //   console.log(env.PORT);

      import { loadEnv, type LoadEnvOptions } from "./runtime/node-loader";

      ${blocks}
    '';

  # ===========================================================================
  # File entries
  # ===========================================================================

  packageJsonValue =
    let
      exportsAttrset =
        {
          "." = {
            default = "./src/index.ts";
          };
          "./runtime" = {
            default = "./src/runtime/node-loader.ts";
          };
        }
        // lib.listToAttrs (
          map (app: {
            name = "./${app}";
            value = {
              default = "./src/exports/${app}.ts";
            };
          }) appsWithEnv
        );
    in
    {
      name = packageName;
      type = "module";
      bin = {
        "docker-entrypoint" = "./src/runtime/docker-entrypoint.ts";
      };
      exports = exportsAttrset;
      dependencies = {
        "sops-age" = "^4.0.2";
        # Effect powers the runtime loaders (loader.ts + node-loader.ts).
        # `@effect/platform-{node,bun}` are loaded lazily by node-loader.ts —
        # the unused one is never imported at runtime, but both must resolve.
        effect = "4.0.0-beta.43";
        "@effect/platform-node" = "4.0.0-beta.43";
        "@effect/platform-bun" = "4.0.0-beta.43";
      };
      devDependencies = {
        typescript = "^5.9.3";
      };
    };

  tsconfigValue = {
    compilerOptions = {
      target = "ESNext";
      module = "ESNext";
      moduleResolution = "bundler";
      lib = [ "ESNext" ];
      verbatimModuleSyntax = true;
      strict = true;
      strictNullChecks = true;
      skipLibCheck = true;
      resolveJsonModule = true;
      allowSyntheticDefaultImports = true;
      esModuleInterop = true;
      forceConsistentCasingInFileNames = true;
      isolatedModules = true;
      noUncheckedIndexedAccess = true;
      declaration = true;
      declarationMap = true;
      sourceMap = true;
      outDir = "dist";
      composite = true;
    };
    include = [ "src" ];
    exclude = [
      "node_modules"
      "dist"
    ];
  };

  readmeContent =
    let
      appSections = lib.concatMapStringsSep "\n" (
        appName:
        let
          appEnv = getAppEnv apps.${appName};
          envVarKeys = lib.sort (a: b: a < b) (lib.attrNames appEnv);
          envVarList = lib.concatMapStringsSep ", " (k: "`${k}`") envVarKeys;
          jsName = toJsIdentifier appName;
          firstKey = if envVarKeys != [ ] then lib.head envVarKeys else "PORT";
          envs = availableAppEnvs.${appName} or [ ];
          firstEnv = if envs != [ ] then lib.head (lib.sort (a: b: a < b) envs) else "dev";
          envList = lib.concatMapStringsSep ", " (e: "`${e}`") (lib.sort (a: b: a < b) envs);
        in
        ''
          ### ${appName}

          Environments: ${envList}

          Variables: ${envVarList}

          ```typescript
          import { ${jsName} } from "${packageName}";
          const env = await ${jsName}.${firstEnv}();
          console.log(env.${firstKey});
          ```
        ''
      ) appsWithEnv;
      appCount = toString (lib.length appsWithEnv);
      appCountSuffix = if lib.length appsWithEnv == 1 then "" else "s";
      firstAppJs = if appsWithEnv != [ ] then toJsIdentifier (lib.head appsWithEnv) else "app";
    in
    builtins.replaceStrings
      [
        "{{PACKAGE_NAME}}"
        "{{APP_COUNT}}"
        "{{APP_COUNT_SUFFIX}}"
        "{{FIRST_APP_JS}}"
        "{{APP_SECTIONS}}"
      ]
      [
        packageName
        appCount
        appCountSuffix
        firstAppJs
        appSections
      ]
      templates.readme;

  generatedFiles =
    let
      packageJsonEntry = {
        "${packageDir}/package.json" = {
          kind = "json";
          jsonValue = packageJsonValue;
        };
      };

      tsconfigEntry = {
        "${packageDir}/tsconfig.json" = {
          kind = "json";
          jsonValue = tsconfigValue;
        };
      };

      readmeEntry = lib.optionalAttrs (appsWithEnv != [ ]) {
        "${packageDir}/README.md" = {
          kind = "text";
          content = readmeContent;
        };
      };

      embeddedDataEntry = {
        "${generatedDir}/embedded-data.ts" = {
          kind = "text";
          content = embeddedDataModule;
        };
      };

      manifestEntry = {
        ".stack/gen/codegen/env-manifest.json" = {
          kind = "json";
          jsonValue = envBuildManifest;
        };
      };

      runtimeEntries = {
        "${runtimeDir}/loader.ts" = {
          kind = "text";
          content = templates.loader;
        };
        "${runtimeDir}/node-loader.ts" = {
          kind = "text";
          content = templates.nodeLoader;
        };
        "${runtimeDir}/docker-entrypoint.ts" = {
          kind = "text";
          content = templates.dockerEntrypoint;
        };
        "${runtimeDir}/app-env-types.ts" = {
          kind = "text";
          content = appEnvTypesModule;
        };
        "${payloadRuntimeDir}/registry.ts" = {
          kind = "text";
          content = templates.payloadRegistry;
        };
      };

      perAppExports = lib.listToAttrs (
        map (appName: {
          name = "${exportsDir}/${appName}.ts";
          value = {
            kind = "text";
            content = mkAppEnvExport appName;
          };
        }) appsWithEnv
      );

      rootBarrel = lib.optionalAttrs (appsWithEnv != [ ]) {
        "${generatedDir}/index.ts" = {
          kind = "text";
          content = mkRootIndexModule;
        };
      };
    in
    packageJsonEntry
    // tsconfigEntry
    // readmeEntry
    // embeddedDataEntry
    // manifestEntry
    // runtimeEntries
    // perAppExports
    // rootBarrel;

  fileEntries = lib.mapAttrs (
    _path: entry:
      if entry.kind or "text" == "json" then
        {
          type = "json";
          jsonValue = entry.jsonValue;
          source = "codegen/env-package.nix";
          description = "Auto-generated env package file";
        }
      else
        {
          type = "text";
          text = entry.content;
          source = "codegen/env-package.nix";
          description = "Auto-generated env package file";
        }
  ) generatedFiles;
in
{
  inherit generatedFiles fileEntries mergedAppEnvs;

  enabled = apps != { } && lib.any (appCfg: (appCfg.env or { }) != { }) (lib.attrValues apps);
}
