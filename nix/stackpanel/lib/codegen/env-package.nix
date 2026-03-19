# ==============================================================================
# env-package.nix
#
# Generates the env package directly in the target package directory.
#   - Source files under packageDir/src/ are generated.
#   - Root package.json and tsconfig.json are generated too.
#
# Structure:
#   packageDir/
#     package.json       — exports "." and "./<app>"
#     tsconfig.json      — includes src/
#     README.md          — generated package docs
#     src/               — 100% generated (do not edit)
#       <app>/<env>.ts, <app>/index.ts, index.ts
#       <app>.ts, entrypoints/<app>.ts, loader.ts, embedded-data.ts, docker-entrypoint.ts
# ==============================================================================
{ lib, config, ... }:
let
  cfg = config.stackpanel;
  apps = cfg.apps or { };
  users = cfg.users or { };
  secretsCfg = cfg.secrets or { };
  variables = cfg.variables or { };
  packageName = cfg.env.package-name or "@gen/env";

  repoRoot = ../../../..;

  resolveProjectPath = path: if lib.hasPrefix "/" path then path else "${toString repoRoot}/${path}";

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

  # Output directories: generated package at packageDir/
  packageDir = cfg.env.output-dir or "packages/gen/env";
  generatedDir = "${packageDir}/src";
  entrypointsDir = "${generatedDir}/entrypoints";

  # Variables backend determines whether SOPS files are generated
  variablesBackend = cfg.secrets.backend or "vals";
  isChamber = variablesBackend == "chamber";

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
    entrypoint = builtins.readFile "${templateDir}/entrypoint.tmpl.ts";
    envExport = builtins.readFile "${templateDir}/env-export.tmpl.ts";
    index = builtins.readFile "${templateDir}/index.ts";
    loader = builtins.readFile "${templateDir}/loader.ts";
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
      # For prod, we might want restricted access
      isProd = envName == "prod" || envName == "production";
      # Get environment-specific allowed keys (if configured)
      envAllowedUsers = envCfg.allowed-users or null;

      # Determine which keys to include
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

  # Collect all app/env combinations
  allEnvs = lib.concatLists (
    lib.mapAttrsToList (
      appName: appCfg:
      lib.mapAttrsToList (envName: envCfg: {
        inherit appName envName envCfg;
      }) (appCfg.environments or { })
    ) apps
  );

  # Generate all SOPS rules
  sopsRules = map (
    {
      appName,
      envName,
      envCfg,
    }:
    mkSopsRule appName envName envCfg
  ) allEnvs;

  # Shared vars rule (unencrypted)
  sharedVarsRule = {
    path_regex = "^shared/vars\\.yaml$";
    unencrypted_regex = ".*";
  };

  # Catch-all rule for any other files
  catchAllRule = {
    path_regex = ".*\\.yaml$";
    key_groups = [
      {
        age = lib.unique (baseKeys ++ validUserKeys);
      }
    ];
  };

  # Generate .sops.yaml content
  sopsYamlContent =
    let
      # Format a key group
      formatKeyGroup = kg: "      - age:\n" + lib.concatMapStringsSep "" (k: "          - ${k}\n") kg.age;

      # Format a creation rule
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
  # Embedded Runtime Data
  # ===========================================================================

  normalizeEnvVars = lib.mapAttrs (_: value: builtins.toString value);

  sharedVarsObject = lib.listToAttrs (
    lib.concatMap (
      variableId:
      let
        variable = variables.${variableId};
        keyGroup = if variable ? keyGroup then variable.keyGroup else getKeyGroup variable.id;
      in
      lib.optional (keyGroup == "var") {
        name = if variable ? varName then variable.varName else getVarName variable.id;
        value = builtins.toString variable.value;
      }
    ) (lib.attrNames variables)
  );

  computedVarsObject = lib.listToAttrs (
    lib.concatMap (
      variableId:
      let
        variable = variables.${variableId};
        keyGroup = if variable ? keyGroup then variable.keyGroup else getKeyGroup variable.id;
      in
      lib.optional (keyGroup == "computed") {
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
        value = lib.genAttrs envNames (envName: normalizeEnvVars (envs.${envName}.env or { }));
      }
    ) (lib.attrNames apps)
  );

  secretVariables = lib.filterAttrs (
    _: variable:
    let
      keyGroup = if variable ? keyGroup then variable.keyGroup else getKeyGroup variable.id;
    in
    keyGroup == "secret"
  ) variables;

  secretFileContents = lib.listToAttrs (
    lib.concatMap (
      variableId:
      let
        filePath = "${
          resolveProjectPath (secretsCfg.secrets-dir or ".stack/secrets")
        }/vars/${secretFileStem variableId}.sops.yaml";
      in
      lib.optional (builtins.pathExists filePath) {
        name = variableId;
        value = builtins.readFile filePath;
      }
    ) (lib.attrNames secretVariables)
  );

  secretYamlKeys = lib.mapAttrs' (variableId: _: {
    name = variableId;
    value = secretYamlKey variableId;
  }) secretVariables;

  embeddedDataModule = ''
    // Auto-generated by Stackpanel — do not edit manually.
    export const SHARED_VARS = ${builtins.toJSON sharedVarsObject} as Record<string, string>;
    export const COMPUTED_VARS = ${builtins.toJSON computedVarsObject} as Record<string, string>;
    export const APP_ENVS = ${builtins.toJSON appEnvObjects} as Record<string, Record<string, Record<string, string>>>;
    export const SECRET_FILE_CONTENTS = ${builtins.toJSON secretFileContents} as Record<string, string>;
    export const SECRET_YAML_KEYS = ${builtins.toJSON secretYamlKeys} as Record<string, string>;
  '';

  # ===========================================================================
  # TypeScript Codegen
  # ===========================================================================

  # Generate TypeScript module for an app/env
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

  # Generate barrel export (used for both per-app and root barrels)
  mkBarrelExport =
    names:
    let
      sorted = lib.sort (a: b: a < b) names;
      exports = lib.concatMapStringsSep "\n" (n: "export * as ${toJsIdentifier n} from './${n}';") sorted;
    in
    builtins.replaceStrings [ "{{EXPORTS}}" ] [ exports ] templates.barrel;

  # ===========================================================================
  # Entrypoint Generation
  # ===========================================================================

  # Generate entrypoint for an app
  mkAppEntrypoint =
    appName: appCfg:
    let
      envNames = lib.attrNames (appCfg.environments or { });
    in
    builtins.replaceStrings [ "{{APP_NAME}}" "{{VALID_ENVS}}" ] [ appName (builtins.toJSON envNames) ]
      templates.entrypoint;

  # Generate app-level env export (so @gen/env/web gives env)
  mkAppEnvExport =
    appName: appCfg:
    let
      envNames = lib.attrNames (
        lib.filterAttrs (_: e: (e.env or { }) != { }) (appCfg.environments or { })
      );
      envCases = lib.concatMapStringsSep "\n" (
        e: "  if (envName === \"${e}\") return (app as any).${toJsIdentifier e}.getEnv();"
      ) envNames;
    in
    builtins.replaceStrings [ "{{APP_NAME}}" "{{ENV_CASES}}" ] [ appName envCases ] templates.envExport;

  # ===========================================================================
  # Collect All Generated Files
  # ===========================================================================

  generatedFiles =
    let
      # Per-app/env TypeScript modules
      tsModules = lib.listToAttrs (
        lib.concatMap (
          {
            appName,
            envName,
            envCfg,
          }:
          let
            content = mkEnvTsModule appName envName envCfg;
            path = "${generatedDir}/${appName}/${envName}.ts";
          in
          lib.optional (content != null) {
            name = path;
            value = content;
          }
        ) allEnvs
      );

      # Per-app barrel exports
      appBarrels = lib.listToAttrs (
        lib.concatMap (
          appName:
          let
            appCfg = apps.${appName};
            envs = appCfg.environments or { };
            envNames = lib.attrNames (lib.filterAttrs (_: e: (e.env or { }) != { }) envs);
            path = "${generatedDir}/${appName}/index.ts";
          in
          lib.optional (envNames != [ ]) {
            name = path;
            value = mkBarrelExport envNames;
          }
        ) (lib.attrNames apps)
      );

      # Root barrel export
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
        "${generatedDir}/index.ts" = mkBarrelExport appsWithEnvs;
      };

      # Entrypoints
      entrypoints = lib.listToAttrs (
        lib.concatMap (
          appName:
          let
            appCfg = apps.${appName};
            hasEnvs = (appCfg.environments or { }) != { };
            path = "${entrypointsDir}/${appName}.ts";
          in
          lib.optional hasEnvs {
            name = path;
            value = mkAppEntrypoint appName appCfg;
          }
        ) (lib.attrNames apps)
      );

      # Entrypoints barrel
      entrypointsBarrel = lib.optionalAttrs (entrypoints != { }) {
        "${entrypointsDir}/index.ts" = mkBarrelExport (lib.attrNames apps);
      };

      # App-level env exports (so @gen/env/web resolves to env)
      appExports = lib.listToAttrs (
        lib.concatMap (
          appName:
          let
            appCfg = apps.${appName};
            envNames = lib.attrNames (
              lib.filterAttrs (_: e: (e.env or { }) != { }) (appCfg.environments or { })
            );
            path = "${generatedDir}/${appName}.ts";
          in
          lib.optional (envNames != [ ]) {
            name = path;
            value = mkAppEnvExport appName appCfg;
          }
        ) (lib.attrNames apps)
      );

      # Root package.json — exports point into gen/ (no mixing of generated and source)
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
            ++ (map (app: {
              name = "./${app}";
              value = {
                default = "./src/${app}.ts";
              };
            }) (appsWithEnvs ++ manualExportNames))
          );
          packageJsonAttr = {
            name = packageName;
            type = "module";
            bin = {
              "docker-entrypoint" = "./src/docker-entrypoint.ts";
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
        "${packageDir}/package.json" = rootPackageJsonContent;
      };

      tsconfigJson = {
        "${packageDir}/tsconfig.json" = builtins.toJSON {
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
        "${packageDir}/README.md" =
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

      embeddedDataFile = {
        "${generatedDir}/embedded-data.ts" = embeddedDataModule;
      };

      loader = {
        "${generatedDir}/loader.ts" = templates.loader;
      };

      dockerEntrypoint = {
        "${generatedDir}/docker-entrypoint.ts" = templates.dockerEntrypoint;
      };
    in
    packageJson
    // tsconfigJson
    // rootReadme
    // embeddedDataFile
    // loader
    // dockerEntrypoint
    // tsModules
    // appBarrels
    // rootBarrel
    // entrypoints
    // entrypointsBarrel
    // appExports;

  # Convert to stackpanel.files.entries format
  fileEntries = lib.mapAttrs (path: content: {
    type = "text";
    text = content;
    source = "codegen/env-package.nix";
    description = "Auto-generated env package file";
  }) generatedFiles;

in
{
  inherit generatedFiles fileEntries;

  # Individual parts for inspection
  sopsYaml = sopsYamlContent;
  sopsRules = sopsRules;
  allEnvs = allEnvs;

  # Check if generation is needed
  enabled =
    apps != { } && lib.any (appCfg: (appCfg.environments or { }) != { }) (lib.attrValues apps);
}
