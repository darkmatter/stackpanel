# ==============================================================================
# env-package.nix
#
# Generates the env package directly in the target package directory.
#   - Source files under packageDir/src/ are generated.
#   - Root package.json and tsconfig.json are generated too.
#   - Runtime payload metadata stays in Nix; encrypted env payloads are built
#     by the host-side `stackpanel codegen build` command.
#
# Structure:
#   packageDir/
#     package.json       — exports "." and "./<app>"
#     tsconfig.json      — includes src/
#     README.md          — generated package docs
#     src/               — 100% generated (do not edit)
#       apps/<app>/<env>.ts
#       apps/<app>/index.ts
#       exports/<app>.ts
#       runtime/loader.ts, runtime/node-loader.ts, runtime/docker-entrypoint.ts
#       runtime/generated-payloads/<app>/<env>.ts
#       runtime/generated-payloads/registry.ts
#       embedded-data.ts, index.ts
# ==============================================================================
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.stackpanel;
  apps = cfg.apps or { };
  users = cfg.users or { };
  secretsCfg = cfg.secrets or { };
  variables = cfg.variables or { };
  packageName = cfg.env.package-name or "@gen/env";
  explicitEnvReferences = cfg.env.references or { };

  # Per-app environment variable metadata (from environmentVariables field)
  getAppEnvVarMeta = appCfg: appCfg.environmentVariables or { };
  isSecretEnvVar = appCfg: envKey:
    let
      meta = getAppEnvVarMeta appCfg;
      varMeta = meta.${envKey} or null;
    in
    varMeta != null && (varMeta.secret or false);
  getEnvVarDefault = appCfg: envKey:
    let
      meta = getAppEnvVarMeta appCfg;
      varMeta = meta.${envKey} or null;
    in
    if varMeta != null then varMeta.defaultValue or null else null;

  repoRoot = ../../../..;
  projectRoot =
    if config.stackpanel.root != null then
      config.stackpanel.root
    else if builtins.getEnv "PWD" != "" then
      builtins.getEnv "PWD"
    else
      toString repoRoot;
  resolveProjectPath = path: if lib.hasPrefix "/" path then path else "${projectRoot}/${path}";

  getKeyGroup =
    id:
    let
      cleaned = lib.removePrefix "/" id;
      parts = lib.splitString "/" cleaned;
    in
    if parts != [ ] then builtins.head parts else "var";

  getVarName =
    id:
    let
      cleaned = lib.removePrefix "/" id;
      parts = lib.splitString "/" cleaned;
    in
    if parts != [ ] then lib.last parts else id;

  secretFileStem = id: builtins.replaceStrings [ "/" "\\" " " ] [ "-" "-" "-" ] (getVarName id);

  secretYamlKey = id: builtins.replaceStrings [ "-" "." "/" " " ] [ "_" "_" "_" "_" ] (getVarName id);

  parseVariableLink =
    value:
    if lib.hasPrefix "var://" value then
      let
        rawId = lib.removePrefix "var://" value;
      in
      if rawId == "" then
        null
      else if lib.hasPrefix "/" rawId then
        rawId
      else
        "/${rawId}"
    # Bare /<group>/<key> paths are shorthand for var://<group>/<key>
    else if lib.hasPrefix "/" value && builtins.stringLength value > 1 then
      value
    else
      null;

  parseSopsReference =
    value:
    let
      matches = builtins.match "ref\\+sops://([^#]+)#/(.+)" value;
    in
    if matches == null then
      null
    else
      {
        path = builtins.elemAt matches 0;
        key = builtins.elemAt matches 1;
      };

  inferSopsFileType =
    path:
    if lib.hasSuffix ".sops.json" path || lib.hasSuffix ".json" path then
      "json"
    else if lib.hasSuffix ".sops.env" path || lib.hasSuffix ".env" path then
      "env"
    else
      "yaml";

  # Output directories: generated package at packageDir/
  packageDir = cfg.env.output-dir or "packages/gen/env";
  dataDir = "${packageDir}/data";
  generatedDir = "${packageDir}/src";
  appsDir = "${generatedDir}/apps";
  exportsDir = "${generatedDir}/exports";
  runtimeDir = "${generatedDir}/runtime";
  payloadRuntimeDir = "${runtimeDir}/generated-payloads";

  # ===========================================================================
  # Templates — read from ./templates/env/ (no inlined TS/JSON in Nix)
  #
  #   *.tmpl.*  — template files with {{PLACEHOLDER}} substitution
  #   *.*       — static files copied verbatim
  # ===========================================================================
  templateDir = ./templates/env;

  templates = {
    envModule = builtins.readFile "${templateDir}/env-module.tmpl.ts";
    barrel = builtins.readFile "${templateDir}/barrel.tmpl.ts";
    envExport = builtins.readFile "${templateDir}/env-export.tmpl.ts";
    index = builtins.readFile "${templateDir}/index.ts";
    loader = builtins.readFile "${templateDir}/loader.ts";
    nodeLoader = builtins.readFile "${templateDir}/node-loader.ts";
    payloadRegistry = builtins.readFile "${templateDir}/payload-registry.ts";
    dockerEntrypoint = builtins.readFile "${templateDir}/docker-entrypoint.ts";
    packageJson = builtins.readFile "${templateDir}/package.json.tmpl";
    tsconfig = builtins.readFile "${templateDir}/tsconfig.json";
    readme = builtins.readFile "${templateDir}/README.tmpl.md";
  };

  # Convert hyphenated names to valid JS identifiers (camelCase)
  # e.g., "stackpanel-go" -> "stackpanelGo"
  toJsIdentifier =
    name:
    let
      parts = lib.splitString "-" name;
      capitalize = s: lib.toUpper (lib.substring 0 1 s) + lib.substring 1 (-1) s;
      first = lib.head parts;
      rest = map capitalize (lib.tail parts);
    in
    lib.concatStrings ([ first ] ++ rest);

  # Collect all user AGE keys
  userKeys = lib.mapAttrsToList (_: user: user.age-public-key or null) users;
  validUserKeys = lib.filter (k: k != null) userKeys;
  configuredRecipients = secretsCfg.recipients or { };
  configuredRecipientKeys = lib.filter (k: k != null) (
    lib.mapAttrsToList (_: recipient: recipient.public-key or null) configuredRecipients
  );

  envRecipientTags =
    envName:
    lib.unique (
      [ envName ]
      ++ lib.optional (envName == "prod") "production"
      ++ lib.optional (envName == "production") "prod"
    );

  envPayloadRecipients =
    envName:
    let
      tags = envRecipientTags envName;
      taggedRecipients = lib.filter (k: k != null) (
        lib.mapAttrsToList (
          _: recipient:
          let
            recipientTags = recipient.tags or [ ];
          in
          if recipientTags == [ ] || lib.any (tag: lib.elem tag recipientTags) tags then
            recipient.public-key or null
          else
            null
        ) configuredRecipients
      );
      fallbackRecipients = taggedRecipients ++ configuredRecipientKeys ++ validUserKeys;
    in
    lib.unique fallbackRecipients;

  # Group names are still used for file organization, but Stackpanel no longer
  # generates a dedicated AGE keypair per group.
  groups = secretsCfg.groups or { };

  # All non-user keys have been removed from the direct SOPS recipient set.
  baseKeys = [ ];

  # ===========================================================================
  # SOPS Config Generation
  # ===========================================================================

  # Generate SOPS creation rule for an app/env
  mkSopsRule =
    appName: envName: envCfg:
    let
      isProd = envName == "prod" || envName == "production";
      envAllowedUsers = envCfg.allowed-users or null;
      keys =
        if envAllowedUsers != null then
          lib.filter (k: k != null) (map (u: (users.${u} or { }).age-public-key or null) envAllowedUsers)
        else if isProd then
          [ ]
        else
          validUserKeys;
    in
    {
      path_regex = "^${appName}/${envName}\\.yaml$";
      key_groups = [
        {
          age = lib.unique keys;
        }
      ];
    };

  allEnvs = lib.concatLists (
    lib.mapAttrsToList (
      appName: appCfg:
      lib.mapAttrsToList (envName: envCfg: {
        inherit appName envName envCfg;
      }) (appCfg.environments or { })
    ) apps
  );

  sopsRules = map (
    {
      appName,
      envName,
      envCfg,
    }:
    mkSopsRule appName envName envCfg
  ) allEnvs;

  sharedVarsRule = {
    path_regex = "^shared/vars\\.yaml$";
    unencrypted_regex = ".*";
  };

  catchAllRule = {
    path_regex = ".*\\.yaml$";
    key_groups = [
      {
        age = lib.unique (baseKeys ++ validUserKeys);
      }
    ];
  };

  sopsYamlContent =
    let
      formatKeyGroup = kg: "      - age:\n" + lib.concatMapStringsSep "" (k: "          - ${k}\n") kg.age;
      formatRule =
        rule:
        if rule ? unencrypted_regex then
          "  - path_regex: ${rule.path_regex}\n    unencrypted_regex: \"${rule.unencrypted_regex}\"\n"
        else
          "  - path_regex: ${rule.path_regex}\n    key_groups:\n"
          + lib.concatMapStringsSep "" formatKeyGroup rule.key_groups;
      allRules = [ sharedVarsRule ] ++ sopsRules ++ [ catchAllRule ];
    in
    ''
      # Auto-generated by Stackpanel - do not edit manually
      # Regenerate with: write-files or restart devshell
      #
      # Structure:
      #   shared/vars.yaml - Plaintext shared config (NOT encrypted)
      #   <app>/<env>.yaml - Per-app per-env secrets (SOPS encrypted)

      keys:
      ${lib.optionalString (validUserKeys != [ ]) ''
          # Team member keys
        ${lib.concatMapStringsSep "" (k: "  - ${k}\n") validUserKeys}''}

      creation_rules:
      ${lib.concatMapStringsSep "" formatRule allRules}
    '';

  # ===========================================================================
  # Runtime Payload Data
  # ===========================================================================

  normalizeEnvVars = lib.mapAttrs (_: value: builtins.toString value);

  computedVarsObject = lib.listToAttrs (
    lib.concatMap (
      variableId:
      let
        variable = variables.${variableId};
        isComputedVariable =
          if variable ? isComputed then variable.isComputed else getKeyGroup variable.id == "computed";
      in
      lib.optional isComputedVariable {
        name = variable.id;
        value = builtins.toString variable.value;
      }
    ) (lib.attrNames variables)
  );

  appEnvObjects = lib.listToAttrs (
    lib.concatMap (
      appName:
      let
        appCfg = apps.${appName};
        envs = appCfg.environments or { };
        envNames = lib.attrNames (lib.filterAttrs (_: e: (e.env or { }) != { }) envs);
      in
      lib.optional (envNames != [ ]) {
        name = appName;
        value = envNames;
      }
    ) (lib.attrNames apps)
  );

  groupedVariables = lib.filterAttrs (
    _: variable:
    let
      isComputedVariable =
        if variable ? isComputed then variable.isComputed else getKeyGroup variable.id == "computed";
    in
    !isComputedVariable
  ) variables;

  groupFilePathForVariable =
    variableId:
    let
      variable = groupedVariables.${variableId} or { };
      configuredPath =
        variable.sopsFile
          or "${secretsCfg.secrets-dir or ".stack/secrets"}/vars/${getKeyGroup variableId}.sops.yaml";
    in
    configuredPath;

  groupYamlKeyForVariable =
    variableId:
    let
      variable = groupedVariables.${variableId} or { };
    in
    variable.secretYamlKey or (secretYamlKey variableId);

  inferVariableIdForEmptyEnvValue =
    envName: envKey:
    let
      normalizedEnvKey = builtins.replaceStrings [ "-" "." "/" " " ] [ "_" "_" "_" "_" ] (
        lib.toLower envKey
      );
      candidates = lib.filter (variableId: groupYamlKeyForVariable variableId == normalizedEnvKey) (
        lib.attrNames groupedVariables
      );
      envCandidates = lib.filter (variableId: getKeyGroup variableId == envName) candidates;
      devCandidates = lib.filter (variableId: getKeyGroup variableId == "dev") candidates;
      secretCandidates = lib.filter (variableId: getKeyGroup variableId == "secret") candidates;
    in
    if envCandidates != [ ] then
      lib.head envCandidates
    else if devCandidates != [ ] then
      lib.head devCandidates
    else if secretCandidates != [ ] then
      lib.head secretCandidates
    else if builtins.length candidates == 1 then
      lib.head candidates
    else
      null;

  inferVariableIdFromSourcePos =
    envVars: envKey:
    let
      pos = builtins.unsafeGetAttrPos envKey envVars;
      file = if pos != null && pos ? file then pos.file else null;
      line = if pos != null && pos ? line then pos.line else null;
    in
    if file == null || line == null || !(builtins.pathExists file) then
      null
    else
      let
        lines = lib.splitString "\n" (builtins.readFile file);
        start = if line > 0 then line - 1 else 0;
        snippet = lib.concatStringsSep " " (lib.take 5 (lib.drop start lines));
        match = builtins.match ''.*config\.variables\."([^"]+)"\.value.*'' snippet;
      in
      if match == null then null else builtins.elemAt match 0;

  mkEnvResolutionEntries =
    appName: envName: envCfg:
    let
      rawEnvVars = envCfg.env or { };
      envVars = normalizeEnvVars rawEnvVars;
      envReferences = (explicitEnvReferences.${appName} or { }).${envName} or { };
    in
    lib.mapAttrs (
      envKey: value:
      let
        variableId = parseVariableLink value;
        sopsRef = parseSopsReference value;
        explicitVariableId = envReferences.${envKey} or null;
        sourceVariableId = if value == "" then inferVariableIdFromSourcePos rawEnvVars envKey else null;
        inferredVariableId = if value == "" then inferVariableIdForEmptyEnvValue envName envKey else null;
        variable =
          if variableId != null && builtins.hasAttr variableId variables then
            variables.${variableId}
          else if explicitVariableId != null && builtins.hasAttr explicitVariableId variables then
            variables.${explicitVariableId}
          else if sourceVariableId != null && builtins.hasAttr sourceVariableId variables then
            variables.${sourceVariableId}
          else if inferredVariableId != null && builtins.hasAttr inferredVariableId variables then
            variables.${inferredVariableId}
          else
            null;
        isComputedVariable =
          (
            variableId != null
            || explicitVariableId != null
            || sourceVariableId != null
            || inferredVariableId != null
          )
          && (
            if variable != null && variable ? isComputed then
              variable.isComputed
            else
              getKeyGroup (
                if variableId != null then
                  variableId
                else if explicitVariableId != null then
                  explicitVariableId
                else if sourceVariableId != null then
                  sourceVariableId
                else
                  inferredVariableId
              ) == "computed"
          );
        effectiveVariableId =
          if variableId != null then
            variableId
          else if explicitVariableId != null then
            explicitVariableId
          else if sourceVariableId != null then
            sourceVariableId
          else
            inferredVariableId;
      in
      if sopsRef != null then
        {
          kind = "sopsRef";
          path = sopsRef.path;
          fileType = inferSopsFileType sopsRef.path;
          key = sopsRef.key;
        }
      else if isComputedVariable then
        {
          kind = "literal";
          value =
            if builtins.hasAttr effectiveVariableId computedVarsObject then
              computedVarsObject.${effectiveVariableId}
            else if variable != null then
              builtins.toString variable.value
            else
              throw "env-package: missing computed variable ${effectiveVariableId}";
        }
      else if effectiveVariableId != null then
        {
          kind = "group";
          variableId = effectiveVariableId;
          path = groupFilePathForVariable effectiveVariableId;
          fileType = inferSopsFileType (groupFilePathForVariable effectiveVariableId);
          key = groupYamlKeyForVariable effectiveVariableId;
        }
      else
        {
          kind = "literal";
          value = value;
        }
    ) envVars;

  # Per-app environmentVariables metadata for the build manifest
  appEnvVarsMeta = lib.filterAttrs (_: v: v != { }) (
    lib.mapAttrs (_appName: appCfg: getAppEnvVarMeta appCfg) apps
  );

  envBuildManifest = {
    schemaVersion = 1;
    dataRoot = dataDir;
    environmentVariables = lib.mapAttrs (
      _appName: meta:
      lib.mapAttrs (
        _varName: varMeta: {
          key = varMeta.key or _varName;
          required = varMeta.required or false;
          secret = varMeta.secret or false;
          defaultValue = varMeta.defaultValue or null;
        }
      ) meta
    ) appEnvVarsMeta;
    targets = map (
      {
        appName,
        envName,
        envCfg,
      }:
      {
        app = appName;
        environment = envName;
        outputPath = "${dataDir}/${envName}/${appName}.sops.json";
        recipients = lib.sort (a: b: a < b) (envPayloadRecipients envName);
        vars = mkEnvResolutionEntries appName envName envCfg;
      }
    ) (lib.filter ({ envCfg, ... }: (envCfg.env or { }) != { }) allEnvs);
  };

  embeddedDataModule = ''
    // Auto-generated by Stackpanel — do not edit manually.
    export const AVAILABLE_APP_ENVS = ${builtins.toJSON appEnvObjects} as Record<string, string[]>;

    export interface EnvVarMeta {
      key: string;
      required: boolean;
      secret: boolean;
      defaultValue: string | null;
    }
    export const ENVIRONMENT_VARIABLES = ${builtins.toJSON appEnvVarsMeta} as Record<string, Record<string, EnvVarMeta>>;
  '';

  # ===========================================================================
  # TypeScript Codegen
  # ===========================================================================

  mkEnvTsModule =
    appName: envName: envCfg:
    let
      envVars = envCfg.env or { };
      sortedKeys = lib.sort (a: b: a < b) (lib.attrNames envVars);
      fields = lib.concatMapStringsSep "\n" (key: "  ${key}: string;") sortedKeys;
    in
    if envVars == { } then
      null
    else
      builtins.replaceStrings [ "{{FIELDS}}" ] [ fields ] templates.envModule;

  mkBarrelExport =
    names: basePath:
    let
      sorted = lib.sort (a: b: a < b) names;
      exports = lib.concatMapStringsSep "\n" (
        n: "export * as ${toJsIdentifier n} from '${basePath}${n}';"
      ) sorted;
    in
    builtins.replaceStrings [ "{{EXPORTS}}" ] [ exports ] templates.barrel;

  # ===========================================================================
  # Entrypoint Generation
  # ===========================================================================

  mkAppEnvExport =
    appName: appCfg:
    let
      envNames = lib.sort (a: b: a < b) (
        lib.attrNames (lib.filterAttrs (_: e: (e.env or { }) != { }) (appCfg.environments or { }))
      );
      defaultEnv = if envNames != [ ] then lib.head envNames else "dev";
      envType = lib.concatMapStringsSep " | " (e: "app.${toJsIdentifier e}.Env") envNames;
      envCases = lib.concatMapStringsSep "\n" (
        e: "  if (envName === \"${e}\") return app.${toJsIdentifier e}.getEnv(processEnv);"
      ) envNames;
    in
    builtins.replaceStrings
      [ "{{APP_NAME}}" "{{ENV_CASES}}" "{{ENV_TYPE}}" "{{DEFAULT_ENV}}" "{{DEFAULT_ENV_IDENT}}" ]
      [ appName envCases envType defaultEnv (toJsIdentifier defaultEnv) ]
      templates.envExport;

  # ===========================================================================
  # Collect All Generated Files
  # ===========================================================================

  generatedFiles =
    let
      tsModules = lib.listToAttrs (
        lib.concatMap (
          {
            appName,
            envName,
            envCfg,
          }:
          let
            content = mkEnvTsModule appName envName envCfg;
            path = "${appsDir}/${appName}/${envName}.ts";
          in
          lib.optional (content != null) {
            name = path;
            value = {
              kind = "text";
              content = content;
            };
          }
        ) allEnvs
      );

      appBarrels = lib.listToAttrs (
        lib.concatMap (
          appName:
          let
            appCfg = apps.${appName};
            envs = appCfg.environments or { };
            envNames = lib.attrNames (lib.filterAttrs (_: e: (e.env or { }) != { }) envs);
            path = "${appsDir}/${appName}/index.ts";
          in
          lib.optional (envNames != [ ]) {
            name = path;
            value = {
              kind = "text";
              content = mkBarrelExport envNames "./";
            };
          }
        ) (lib.attrNames apps)
      );

      appsWithEnvs = lib.filter (
        appName:
        let
          appCfg = apps.${appName};
          envs = appCfg.environments or { };
        in
        lib.any (e: (e.env or { }) != { }) (lib.attrValues envs)
      ) (lib.attrNames apps);

      manualExportNames =
        lib.filter
          (
            name:
            !(lib.elem name appsWithEnvs)
            && builtins.pathExists (resolveProjectPath "${packageDir}/src/${name}.ts")
          )
          [
            "web"
            "web-client"
            "web-server"
            "auth"
          ];

      rootBarrel = lib.optionalAttrs (appsWithEnvs != [ ]) {
        "${generatedDir}/index.ts" = {
          kind = "text";
          content = mkBarrelExport appsWithEnvs "./exports/";
        };
      };

      appExports = lib.listToAttrs (
        lib.concatMap (
          appName:
          let
            appCfg = apps.${appName};
            envNames = lib.attrNames (
              lib.filterAttrs (_: e: (e.env or { }) != { }) (appCfg.environments or { })
            );
            path = "${exportsDir}/${appName}.ts";
          in
          lib.optional (envNames != [ ]) {
            name = path;
            value = {
              kind = "text";
              content = mkAppEnvExport appName appCfg;
            };
          }
        ) (lib.attrNames apps)
      );

      rootPackageJsonContent =
        let
          exportsAttrset = lib.listToAttrs (
            [
              {
                name = ".";
                value = {
                  default = "./src/index.ts";
                };
              }
            ]
            ++ [
              {
                name = "./runtime";
                value = {
                  default = "./src/runtime/node-loader.ts";
                };
              }
            ]
            ++ (map (app: {
              name = "./${app}";
              value = {
                default = "./src/exports/${app}.ts";
              };
            }) (appsWithEnvs ++ manualExportNames))
          );
          packageJsonAttr = {
            name = packageName;
            type = "module";
            bin = {
              "docker-entrypoint" = "./src/runtime/docker-entrypoint.ts";
            };
            exports = exportsAttrset;
            dependencies = {
              "sops-age" = "^4.0.2";
            };
            devDependencies = {
              typescript = "^5.9.3";
            };
          };
        in
        builtins.toJSON packageJsonAttr;

      packageJson = {
        "${packageDir}/package.json" = {
          kind = "text";
          content = rootPackageJsonContent;
        };
      };

      tsconfigJson = {
        "${packageDir}/tsconfig.json" = {
          kind = "text";
          content = builtins.toJSON {
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
        };
      };

      appSections = lib.concatMapStringsSep "\n" (
        appName:
        let
          appCfg = apps.${appName};
          envs = appCfg.environments or { };
          envNames = lib.sort (a: b: a < b) (
            lib.attrNames (lib.filterAttrs (_: e: (e.env or { }) != { }) envs)
          );
          envList = lib.concatMapStringsSep ", " (e: "`${e}`") envNames;
          jsName = toJsIdentifier appName;
          firstEnv = if envNames != [ ] then lib.head envNames else "dev";
          firstEnvCfg = envs.${firstEnv} or { };
          envVarKeys = lib.sort (a: b: a < b) (lib.attrNames (firstEnvCfg.env or { }));
          envVarList = lib.concatMapStringsSep ", " (k: "`${k}`") envVarKeys;
        in
        ''
          ### ${appName}

          Environments: ${envList}
          Variables: ${envVarList}

          ```typescript
          import { ${jsName} } from "${packageName}";
          const env = ${jsName}.${firstEnv}.getEnv();
          ```
        ''
      ) appsWithEnvs;

      appCount = toString (lib.length appsWithEnvs);
      appCountSuffix = if lib.length appsWithEnvs == 1 then "" else "s";
      firstAppJs = toJsIdentifier (lib.head appsWithEnvs);

      rootReadme = {
        "${packageDir}/README.md" = {
          kind = "text";
          content =
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
        };
      };

      embeddedDataFile = {
        "${generatedDir}/embedded-data.ts" = {
          kind = "text";
          content = embeddedDataModule;
        };
      };

      envManifestFile = {
        ".stack/gen/codegen/env-manifest.json" = {
          kind = "text";
          content = builtins.toJSON envBuildManifest;
        };
      };

      loader = {
        "${runtimeDir}/loader.ts" = {
          kind = "text";
          content = templates.loader;
        };
      };

      nodeLoader = {
        "${runtimeDir}/node-loader.ts" = {
          kind = "text";
          content = templates.nodeLoader;
        };
      };

      payloadRegistry = {
        "${payloadRuntimeDir}/registry.ts" = {
          kind = "text";
          content = templates.payloadRegistry;
        };
      };

      runtimeDockerEntrypoint = {
        "${runtimeDir}/docker-entrypoint.ts" = {
          kind = "text";
          content = templates.dockerEntrypoint;
        };
      };
    in
    packageJson
    // tsconfigJson
    // rootReadme
    // embeddedDataFile
    // envManifestFile
    // loader
    // nodeLoader
    // payloadRegistry
    // runtimeDockerEntrypoint
    // tsModules
    // appBarrels
    // rootBarrel
    // appExports;

  fileEntries = lib.mapAttrs (
    path: entry:
    if entry.kind == "derivation" then
      {
        type = "derivation";
        drv = entry.drv;
        source = "codegen/env-package.nix";
        description = "Auto-generated encrypted env payload";
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
  inherit generatedFiles fileEntries;

  sopsYaml = sopsYamlContent;
  sopsRules = sopsRules;
  allEnvs = allEnvs;

  enabled =
    apps != { }
    && lib.any (
      appCfg:
      (appCfg.environments or { }) != { } || (appCfg.environmentVariables or { }) != { }
    ) (lib.attrValues apps);
}
