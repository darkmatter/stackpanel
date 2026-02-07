# ==============================================================================
# env-package.nix
#
# Generates the complete packages/gen/env structure from stackpanel.apps config:
#   - packages/gen/env/data/.sops.yaml - SOPS creation rules per app/env
#   - packages/gen/env/data/<app>/<env>.yaml - Boilerplate YAML files
#   - packages/gen/env/data/shared/vars.yaml - Shared plaintext config
#   - packages/gen/env/src/generated/<app>/<env>.ts - znv TypeScript modules
#   - packages/gen/env/src/generated/<app>/index.ts - App barrel exports
#   - packages/gen/env/src/generated/index.ts - Root barrel export
#   - packages/gen/env/src/entrypoints/<app>.ts - App entrypoint loaders
#
# This makes packages/gen/env self-contained and portable for Docker.
# ==============================================================================
{ lib, config, ... }:
let
  cfg = config.stackpanel;
  apps = cfg.apps or { };
  users = cfg.users or { };
  secretsCfg = cfg.secrets or { };

  # Variables backend determines whether SOPS files are generated
  variablesBackend = cfg.secrets.backend or "vals";
  isChamber = variablesBackend == "chamber";

  # Output directories (configurable via stackpanel.env.output-dir)
  packageDir = cfg.env.output-dir or "packages/gen/env";
  dataDir = "${packageDir}/data";
  generatedDir = "${packageDir}/src/generated";
  entrypointsDir = "${packageDir}/src/entrypoints";

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

  # Collect group public keys (only from initialized groups with age-pub set)
  groups = secretsCfg.groups or { };
  groupKeys = lib.pipe groups [
    (lib.mapAttrsToList (_: g: g.age-pub or ""))
    (lib.filter (k: k != ""))
  ];

  # Group keys indexed by name for environment-specific matching
  groupsByName = lib.filterAttrs (_: g: (g.age-pub or "") != "") groups;

  # All non-user keys (group keys only — no more global master key)
  baseKeys = groupKeys;

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

      # Match group by environment name (e.g., env "dev" → group "dev")
      # This gives per-env access control: prod secrets only encrypted to prod group
      matchingGroup = groupsByName.${envName} or null;
      matchingGroupKey = if matchingGroup != null then [ matchingGroup.age-pub ] else [ ];

      # Determine which keys to include
      keys =
        if envAllowedUsers != null then
          lib.filter (k: k != null) (map (u: (users.${u} or { }).age-public-key or null) envAllowedUsers)
          ++ matchingGroupKey
        else if isProd then
          matchingGroupKey # Prod: prod group key only (no user keys)
        else
          groupKeys ++ validUserKeys; # Dev/staging: all group keys + user keys
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
      ${lib.optionalString (groupKeys != [ ]) ''
          # Group keys (per-environment access control)
        ${lib.concatStringsSep "" (
          lib.mapAttrsToList (name: g: "  - &group_${name} ${g.age-pub}\n") groupsByName
        )}''}
      ${lib.optionalString (validUserKeys != [ ]) ''
          # Team member keys
        ${lib.concatMapStringsSep "" (k: "  - ${k}\n") validUserKeys}''}

      creation_rules:
      ${lib.concatMapStringsSep "" formatRule allRules}
    '';

  # ===========================================================================
  # YAML Data File Generation (boilerplate)
  # ===========================================================================

  # Generate boilerplate YAML for an app/env
  mkEnvYamlBoilerplate =
    appName: envName: envCfg:
    let
      envVars = envCfg.env or { };
      # Generate key placeholders
      lines = lib.mapAttrsToList (
        key: value:
        let
          # If it's a vals ref, extract the key name for the placeholder
          isRef = lib.hasPrefix "ref+" value;
          placeholder = if isRef then "PLACEHOLDER_${key}" else value;
        in
        "${key}: ${placeholder}"
      ) envVars;
    in
    ''
      # ${appName} ${envName} environment secrets
      # Auto-generated boilerplate - edit values, then encrypt with: sops ${appName}/${envName}.yaml
      ${lib.concatStringsSep "\n" lines}
    '';

  # Shared vars boilerplate
  sharedVarsBoilerplate = ''
    # Shared configuration variables (NOT encrypted)
    # Add non-sensitive config shared across apps/environments

    LOG_LEVEL: info
    API_VERSION: v1
  '';

  # ===========================================================================
  # TypeScript Codegen
  # ===========================================================================

  # Infer Zod schema from value
  inferZodSchema =
    value:
    let
      isValsRef = lib.hasPrefix "ref+" value;
      isNumericStr = builtins.match "^-?[0-9]+\\.?[0-9]*$" value != null;
      isBooleanStr = value == "true" || value == "false";
    in
    if isValsRef then
      "z.string()"
    else if isNumericStr then
      "z.coerce.number()"
    else if isBooleanStr then
      "z.coerce.boolean()"
    else
      "z.string()";

  # Generate TypeScript module for an app/env
  mkEnvTsModule =
    appName: envName: envCfg:
    let
      envVars = envCfg.env or { };
      sortedKeys = lib.sort (a: b: a < b) (lib.attrNames envVars);
      fields = lib.concatMapStringsSep "\n" (
        key:
        let
          value = envVars.${key};
          zodSchema = inferZodSchema value;
        in
        "    ${key}: ${zodSchema},"
      ) sortedKeys;
    in
    if envVars == { } then
      null
    else
      ''
        // Auto-generated by Stackpanel - do not edit manually
        // Run 'write-files' or restart devshell to regenerate
        import { parseEnv, z } from "znv";

        const schema = {
        ${fields}
        };

        let cached: ReturnType<typeof parseEnv<typeof schema>> | null = null;

        export const getEnv = (input: Record<string, string | undefined> = process.env) => {
          if (!cached) cached = parseEnv(input, schema);
          return cached;
        };
      '';

  # Generate app barrel export
  mkAppBarrelExport =
    appName: envNames:
    let
      sorted = lib.sort (a: b: a < b) envNames;
      exports = lib.concatMapStringsSep "\n" (e: "export * as ${toJsIdentifier e} from './${e}';") sorted;
    in
    ''
      // Auto-generated by Stackpanel - do not edit manually
      ${exports}
    '';

  # Generate root barrel export
  mkRootBarrelExport =
    appNames:
    let
      sorted = lib.sort (a: b: a < b) appNames;
      exports = lib.concatMapStringsSep "\n" (a: "export * as ${toJsIdentifier a} from './${a}';") sorted;
    in
    ''
      // Auto-generated by Stackpanel - do not edit manually
      ${exports}
    '';

  # ===========================================================================
  # Entrypoint Generation
  # ===========================================================================

  # Generate entrypoint for an app
  mkAppEntrypoint =
    appName: appCfg:
    let
      envNames = lib.attrNames (appCfg.environments or { });
      envChecks = lib.concatMapStringsSep "\n  " (e: "case '${e}':") envNames;
    in
    ''
      // Auto-generated entrypoint for ${appName}
      // Loads environment-specific secrets at runtime
      import { loadAppEnv } from '../loader';

      const ENV = process.env.NODE_ENV || process.env.APP_ENV || 'dev';

      // Validate environment
      const validEnvs = ${builtins.toJSON envNames};
      if (!validEnvs.includes(ENV)) {
        console.warn(`Unknown environment: ''${ENV}. Using 'dev'.`);
      }

      // Load secrets for this app/environment
      export async function init() {
        const env = validEnvs.includes(ENV) ? ENV : 'dev';
        await loadAppEnv('${appName}', env);
      }

      // Auto-initialize if this is the main module
      if (import.meta.url === `file://''${process.argv[1]}`) {
        init().catch(console.error);
      }
    '';

  # ===========================================================================
  # Collect All Generated Files
  # ===========================================================================

  generatedFiles =
    let
      # .sops.yaml - skip when backend is chamber (secrets in SSM, not SOPS)
      sopsFile = lib.optionalAttrs (!isChamber) {
        "${dataDir}/.sops.yaml" = sopsYamlContent;
      };

      # Shared vars (always generate - these are plaintext /var/* variables)
      sharedFiles = {
        "${dataDir}/shared/vars.yaml" = sharedVarsBoilerplate;
      };

      # Per-app/env YAML boilerplates - skip when backend is chamber
      yamlFiles =
        if isChamber then
          { }
        else
          lib.listToAttrs (
            lib.concatMap (
              {
                appName,
                envName,
                envCfg,
              }:
              let
                content = mkEnvYamlBoilerplate appName envName envCfg;
                path = "${dataDir}/${appName}/${envName}.yaml";
              in
              # Only generate if env has variables defined
              lib.optional ((envCfg.env or { }) != { }) {
                name = path;
                value = content;
              }
            ) allEnvs
          );

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
            value = mkAppBarrelExport appName envNames;
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

      rootBarrel = lib.optionalAttrs (appsWithEnvs != [ ]) {
        "${generatedDir}/index.ts" = mkRootBarrelExport appsWithEnvs;
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
        "${entrypointsDir}/index.ts" =
          let
            appNames = lib.sort (a: b: a < b) (lib.attrNames apps);
            exports = lib.concatMapStringsSep "\n" (
              a: "export * as ${toJsIdentifier a} from './${a}';"
            ) appNames;
          in
          ''
            // Auto-generated by Stackpanel - do not edit manually
            ${exports}
          '';
      };

      # Package scaffolding
      packageJson = {
        "${packageDir}/package.json" = ''
          {
            "name": "@gen/env",
            "type": "module",
            "exports": {
              ".": { "default": "./src/generated/index.ts" },
              "./*": { "default": "./src/*.ts" }
            },
            "dependencies": {
              "znv": "workspace:*",
              "zod": "catalog:"
            },
            "devDependencies": {
              "typescript": "^5.9.3"
            }
          }
        '';
      };

      tsconfigJson = {
        "${packageDir}/tsconfig.json" = ''
          {
            "compilerOptions": {
              "target": "ESNext",
              "module": "ESNext",
              "moduleResolution": "bundler",
              "lib": ["ESNext"],
              "verbatimModuleSyntax": true,
              "strict": true,
              "strictNullChecks": true,
              "skipLibCheck": true,
              "resolveJsonModule": true,
              "allowSyntheticDefaultImports": true,
              "esModuleInterop": true,
              "forceConsistentCasingInFileNames": true,
              "isolatedModules": true,
              "noUncheckedIndexedAccess": true,
              "declaration": true,
              "declarationMap": true,
              "sourceMap": true,
              "outDir": "dist",
              "composite": true
            },
            "exclude": ["node_modules", "dist"]
          }
        '';
      };

      rootIndex = {
        "${packageDir}/src/index.ts" = ''
          // Auto-generated by Stackpanel - do not edit manually
          export * from './generated';
        '';
      };
    in
    packageJson
    // tsconfigJson
    // rootIndex
    // sopsFile
    // sharedFiles
    // yamlFiles
    // tsModules
    // appBarrels
    // rootBarrel
    // entrypoints
    // entrypointsBarrel;

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
