# ==============================================================================
# infra/codegen.nix
#
# Code generation engine for the infrastructure module system.
#
# Generates via stackpanel.files.entries:
#   - src/index.ts       (Infra class with embedded project config)
#   - src/types.ts       (per-module input TypeScript interfaces)
#   - src/resources/*.ts  (custom alchemy resources still needed by infra modules)
#   - modules/<id>.ts    (copied from module path attributes)
#   - alchemy.run.ts     (orchestrator)
#   - package.json       (union of all module dependencies)
#   - tsconfig.json      (TypeScript config)
#
# Also:
#   - Writes infra-inputs.json to state dir
#   - Sets STACKPANEL_INFRA_INPUTS env var
#   - Registers scripts (infra:deploy, infra:destroy, etc.)
#   - Registers as a stackpanel module for UI
#   - Serializes config for the agent
# ==============================================================================
{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.stackpanel.infra;
  projectName = config.stackpanel.name or "my-project";
  outputDir = cfg.output-dir;
  stateDir = config.stackpanel.dirs.state;
  moduleIds = builtins.attrNames cfg.modules;

  sortedModuleIds = lib.sort (a: b: a < b) moduleIds;

  modulePathIsDirectory =
    id:
    let
      modPath = cfg.modules.${id}.path;
    in
    builtins.pathExists (modPath + "/index.ts");

  moduleImportPath =
    id: if modulePathIsDirectory id then "./modules/${id}/index.ts" else "./modules/${id}.ts";

  # ============================================================================
  # Module bunDeps handling
  #
  # External flakes can provide pre-validated bunDeps. When provided,
  # dependencies are already validated at the flake's eval time.
  # ============================================================================

  # Modules that provide their own bunDeps
  modulesWithBunDeps = lib.filterAttrs (_: mod: mod.bunDeps != null) cfg.modules;

  # Modules without bunDeps (deps need runtime or package-level validation)
  modulesWithoutBunDeps = lib.filterAttrs (_: mod: mod.bunDeps == null) cfg.modules;

  # All module bunDeps as a list
  allModuleBunDeps = lib.mapAttrsToList (_: mod: mod.bunDeps) modulesWithBunDeps;

  # Check if all modules provide bunDeps (fully validated at flake level)
  allModulesHaveBunDeps =
    builtins.length (builtins.attrNames modulesWithoutBunDeps) == 0 && builtins.length moduleIds > 0;

  # Check if any module provides bunDeps
  anyModuleHasBunDeps = builtins.length (builtins.attrNames modulesWithBunDeps) > 0;

  # ============================================================================
  # Inputs JSON (written to state dir, read by Infra class at runtime)
  # ============================================================================
  storageBackendConfig =
    if cfg.storage-backend.type == "chamber" then
      {
        type = "chamber";
        service = cfg.storage-backend.chamber.service;
      }
    else if cfg.storage-backend.type == "sops" then
      let
        secretsDir = config.stackpanel.secrets.secrets-dir or ".stack/secrets";
        group = cfg.storage-backend.sops.group;
        resolvedPath = "${secretsDir}/vars/${group}.sops.yaml";
      in
      {
        type = "sops";
        filePath = resolvedPath;
        inherit group;
      }
    else if cfg.storage-backend.type == "ssm" then
      {
        type = "ssm";
        prefix = cfg.storage-backend.ssm.prefix;
      }
    else
      {
        type = "none";
      };

  inputsJson = {
    __config__ = {
      storageBackend = storageBackendConfig;
      keyFormat = cfg.key-format;
      inherit projectName;
    };
  }
  // lib.mapAttrs (_id: mod: mod.inputs) cfg.modules;

  inputsJsonStr = builtins.toJSON inputsJson;

  # ============================================================================
  # Best-effort TypeScript type inference from Nix values
  # ============================================================================
  nixTypeToTs =
    value:
    if builtins.isBool value then
      "boolean"
    else if builtins.isInt value || builtins.isFloat value then
      "number"
    else if builtins.isString value then
      "string"
    else if builtins.isList value then
      "string[]"
    else if builtins.isAttrs value then
      let
        fields = lib.mapAttrsToList (k: v: "  ${lib.strings.toCamelCase k}: ${nixTypeToTs v};") value;
      in
      "{\n${lib.concatStringsSep "\n" fields}\n}"
    else
      "any";

  toPascalCase =
    s:
    let
      parts = lib.splitString "-" s;
      capitalize =
        str:
        let
          first = builtins.substring 0 1 str;
          rest = builtins.substring 1 (builtins.stringLength str) str;
          upper =
            builtins.replaceStrings
              [
                "a"
                "b"
                "c"
                "d"
                "e"
                "f"
                "g"
                "h"
                "i"
                "j"
                "k"
                "l"
                "m"
                "n"
                "o"
                "p"
                "q"
                "r"
                "s"
                "t"
                "u"
                "v"
                "w"
                "x"
                "y"
                "z"
              ]
              [
                "A"
                "B"
                "C"
                "D"
                "E"
                "F"
                "G"
                "H"
                "I"
                "J"
                "K"
                "L"
                "M"
                "N"
                "O"
                "P"
                "Q"
                "R"
                "S"
                "T"
                "U"
                "V"
                "W"
                "X"
                "Y"
                "Z"
              ]
              first;
        in
        upper + rest;
    in
    lib.concatStrings (map capitalize parts);

  # ============================================================================
  # Template processing
  # ============================================================================
  # Templates live in ./templates/ directory:
  #   - *.tmpl.ts  — template files with {{PLACEHOLDER}} substitution
  #   - *.ts       — static files copied verbatim
  # ============================================================================

  # Read and process the Infra class template
  infraTemplate = builtins.readFile ./templates/infra.tpl.ts;
  infraClassTs =
    builtins.replaceStrings [ "__PROJECT_CONFIG__" ] [ (builtins.toJSON inputsJson.__config__) ]
      infraTemplate;

  # Static resource files (no substitution needed)
  iamRoleTs = builtins.readFile ./templates/iam-role.tpl.ts;
  securityGroupTs = builtins.readFile ./templates/security-group.tpl.ts;
  keyPairTs = builtins.readFile ./templates/key-pair.tpl.ts;
  iamInstanceProfileTs = builtins.readFile ./templates/iam-instance-profile.tpl.ts;
  ec2LifecycleTs = builtins.readFile ./templates/ec2-lifecycle.tpl.ts;
  ec2InstanceTs = builtins.readFile ./templates/ec2-instance.tpl.ts;

  # ============================================================================
  # Generated: src/types.ts (per-module input interfaces)
  # ============================================================================
  typesTs =
    let
      interfaces = lib.concatMapStringsSep "\n" (
        id:
        let
          mod = cfg.modules.${id};
          pascalId = toPascalCase id;
          tsType = nixTypeToTs mod.inputs;
        in
        "export interface ${pascalId}Inputs ${tsType}\n"
      ) moduleIds;
    in
    ''
      // Generated by stackpanel — do not edit manually.
      // TypeScript interfaces for infra module inputs.

      ${interfaces}
    '';

  # ============================================================================
  # Generated: alchemy.run.ts (orchestrator)
  #
  # Uses @gen/alchemy for app creation (shared state store config) instead
  # of inline alchemy boilerplate.
  # ============================================================================
  alchemyRunTs =
    let
      legacyProviderImports = ''
        // Register legacy custom-resource providers so pending deletions from
        // earlier generated stacks can still be finalized after migrations.
        import "./src/resources/ec2-instance.ts";
        import "./src/resources/iam-instance-profile.ts";
        import "./src/resources/iam-role.ts";
        import "./src/resources/key-pair.ts";
        import "./src/resources/security-group.ts";
      '';

      # Dynamic imports for each module
      moduleImports = lib.concatMapStringsSep "\n" (
        id:
        let
          mod = cfg.modules.${id};
          syncKeys = builtins.filter (k: (mod.outputs.${k}.sync or false)) (builtins.attrNames mod.outputs);
        in
        ''
          const ${
            builtins.replaceStrings [ "-" ] [ "_" ] id
          }Outputs = (await import("${moduleImportPath id}")).default;
        ''
      ) moduleIds;

      # syncAll argument
      syncAllArg = lib.concatMapStringsSep "\n" (
        id:
        let
          mod = cfg.modules.${id};
          syncKeys = builtins.filter (k: (mod.outputs.${k}.sync or false)) (builtins.attrNames mod.outputs);
          varName = builtins.replaceStrings [ "-" ] [ "_" ] id;
        in
        ''
          "${id}": {
            outputs: ${varName}Outputs,
            syncKeys: ${builtins.toJSON syncKeys},
          },''
      ) moduleIds;

      # Use @gen/alchemy when the deployment Alchemy module is enabled.
      # Otherwise fall back to inline alchemy initialization.
      alchemyCfg = config.stackpanel.deployment.alchemy;
      useGenAlchemy = alchemyCfg.enable;
    in
    if useGenAlchemy then
      ''
        // Generated by stackpanel — do not edit manually.
        import { createApp } from "@gen/alchemy";
        import Infra from "./src/index.ts";
        ${legacyProviderImports}

        const app = await createApp("${projectName}-infra");

        // Import and run infra modules
        ${moduleImports}

        // Sync declared outputs to storage backend
        await Infra.syncAll({
        ${syncAllArg}
        });

        await app.finalize();
      ''
    else
      ''
        // Generated by stackpanel — do not edit manually.
        import alchemy from "alchemy";
        import { CloudflareStateStore } from "alchemy/state";
        import Infra from "./src/index.ts";
        ${legacyProviderImports}

        const app = await alchemy("${projectName}-infra", {
          stateStore: process.env.CLOUDFLARE_API_TOKEN
            ? (scope) =>
                new CloudflareStateStore(scope, {
                  apiToken: alchemy.secret(process.env.CLOUDFLARE_API_TOKEN!),
                })
            : undefined,
        });

        // Import and run infra modules
        ${moduleImports}

        // Sync declared outputs to storage backend
        await Infra.syncAll({
        ${syncAllArg}
        });

        await app.finalize();
      '';

  # ============================================================================
  # Module dependency aggregation (used by turbo.packages)
  # ============================================================================
  allDeps = lib.foldlAttrs (
    acc: _id: mod:
    acc // mod.dependencies
  ) { } cfg.modules;

  # Infra modules must declare concrete dependency versions/ranges.
  # Reject unresolved catalog placeholders to keep generated package.json explicit.
  catalogDepNames = builtins.attrNames (lib.filterAttrs (_: v: v == "catalog:") allDeps);
  validatedDeps =
    if catalogDepNames != [ ] then
      builtins.throw "infra module dependencies must declare explicit versions (found catalog: for ${lib.concatStringsSep ", " catalogDepNames})"
    else
      allDeps;

  # ============================================================================
  # README.md — tailored to registered modules
  # ============================================================================
  readmeMd =
    let
      moduleSections = lib.concatMapStringsSep "\n" (
        id:
        let
          mod = cfg.modules.${id};
          outputKeys = lib.attrNames mod.outputs;
          syncKeys = lib.filter (k: (mod.outputs.${k}.sync or false)) outputKeys;
          depsStr = lib.concatStringsSep ", " (map (d: "`${d}`") (lib.attrNames mod.dependencies));
          outputsStr = lib.concatMapStringsSep "\n" (
            k:
            let
              o = mod.outputs.${k};
              syncTag = if o.sync or false then " *(synced)*" else "";
            in
            "  - \`${k}\` — ${o.description}${syncTag}"
          ) (lib.sort (a: b: a < b) outputKeys);
        in
        ''
          ### ${mod.name} (`${id}`)

          ${mod.description}

          ${lib.optionalString (mod.dependencies != { }) "Dependencies: ${depsStr}\n"}
          **Outputs:**
          ${outputsStr}
        ''
      ) sortedModuleIds;

      storageDesc = {
        "none" = "None (outputs not persisted)";
        "chamber" = "Chamber (AWS SSM Parameter Store via `chamber`)";
        "sops" = "SOPS (encrypted YAML file)";
        "ssm" = "AWS SSM Parameter Store (direct)";
      };
    in
    ''
      # @${projectName}/infra

      > Auto-generated by Stackpanel — do not edit manually.
      > Regenerate with `write-files` or restart devshell.

      Infrastructure-as-code package for **${projectName}**, powered by [Alchemy](https://github.com/sam-goodwin/alchemy).

      ## Modules (${toString (lib.length sortedModuleIds)})

      ${moduleSections}

      ## Usage

      ```bash
      # Deploy all infra modules
      cd ${outputDir} && bun run alchemy.run.ts

      # Destroy all resources
      cd ${outputDir} && bun run alchemy.run.ts --destroy
      ```

      ## Storage Backend

      ${storageDesc.${cfg.storage-backend.type} or "Unknown"}

      ## Architecture

      ```
      ${outputDir}/
      ├── alchemy.run.ts          # Orchestrator (imports all modules, syncs outputs)
      ├── package.json
      ├── tsconfig.json
      ├── src/
      │   ├── index.ts            # Infra class (input resolution, output sync)
      │   └── types.ts            # Per-module TypeScript interfaces
      └── modules/
      ${lib.concatMapStringsSep "" (id: "    ├── ${id}.ts\n") sortedModuleIds}```
    '';

  # ============================================================================
  # Static: tsconfig.json
  # ============================================================================
  tsconfigJsonValue = {
    compilerOptions = {
      target = "ES2022";
      module = "ES2022";
      moduleResolution = "bundler";
      strict = true;
      esModuleInterop = true;
      skipLibCheck = true;
      forceConsistentCasingInFileNames = true;
      resolveJsonModule = true;
      declaration = true;
      declarationMap = true;
      outDir = "./dist";
      rootDir = ".";
    };
    include = [
      "src/**/*.ts"
      "modules/**/*.ts"
      "alchemy.run.ts"
    ];
    exclude = [
      "node_modules"
      "dist"
      ".alchemy"
    ];
  };

  # ============================================================================
  # Module .ts file entries (copied from paths)
  # ============================================================================
  moduleFileEntries = lib.foldlAttrs (
    acc: id: mod:
    if modulePathIsDirectory id then
      let
        entries = builtins.readDir mod.path;
        tsFiles = lib.filterAttrs (name: kind: kind == "regular" && lib.hasSuffix ".ts" name) entries;
        copied = lib.mapAttrs' (
          name: _kind:
          lib.nameValuePair "${outputDir}/modules/${id}/${name}" {
            text = builtins.readFile (mod.path + "/${name}");
            mode = "0644";
            description = "Infra module: ${mod.name} (${name})";
            source = "infra";
          }
        ) tsFiles;
      in
      acc // copied
    else
      acc
      // {
        "${outputDir}/modules/${id}.ts" = {
          text = builtins.readFile mod.path;
          mode = "0644";
          description = "Infra module: ${mod.name}";
          source = "infra";
        };
      }
  ) { } cfg.modules;

in
{
  config = lib.mkIf cfg.enable {
    # ==========================================================================
    # File generation
    # ==========================================================================
    stackpanel.files.entries = {
      # README
      "${outputDir}/README.md" = {
        text = readmeMd;
        mode = "0644";
        description = "Generated README for infra package";
        source = "infra";
      };

      # Infra class library
      "${outputDir}/src/index.ts" = {
        text = infraClassTs;
        mode = "0644";
        description = "Infra class library (@stackpanel/infra)";
        source = "infra";
      };

      # Per-module type interfaces
      "${outputDir}/src/types.ts" = {
        text = typesTs;
        mode = "0644";
        description = "Infra module input type interfaces";
        source = "infra";
      };

      # Custom alchemy resources
      "${outputDir}/src/resources/iam-role.ts" = {
        text = iamRoleTs;
        mode = "0644";
        description = "Custom IAM Role alchemy resource";
        source = "infra";
      };
      "${outputDir}/src/resources/security-group.ts" = {
        text = securityGroupTs;
        mode = "0644";
        description = "Custom Security Group alchemy resource";
        source = "infra";
      };
      "${outputDir}/src/resources/key-pair.ts" = {
        text = keyPairTs;
        mode = "0644";
        description = "Custom Key Pair alchemy resource";
        source = "infra";
      };
      "${outputDir}/src/resources/iam-instance-profile.ts" = {
        text = iamInstanceProfileTs;
        mode = "0644";
        description = "Custom IAM Instance Profile alchemy resource";
        source = "infra";
      };
      "${outputDir}/src/resources/ec2-lifecycle.ts" = {
        text = ec2LifecycleTs;
        mode = "0644";
        description = "EC2 lifecycle helpers (normalization, replacement, migration)";
        source = "infra";
      };
      "${outputDir}/src/resources/ec2-instance.ts" = {
        text = ec2InstanceTs;
        mode = "0644";
        description = "Custom EC2 Instance alchemy resource";
        source = "infra";
      };

      # Orchestrator
      "${outputDir}/alchemy.run.ts" = {
        text = alchemyRunTs;
        mode = "0644";
        description = "Alchemy orchestrator (entrypoint)";
        source = "infra";
      };

      # TSConfig
      "${outputDir}/tsconfig.json" = {
        type = "json";
        jsonValue = tsconfigJsonValue;
        mode = "0644";
        description = "TypeScript configuration for infra package";
        source = "infra";
      };

      # Inputs JSON (state file)
      "${stateDir}/infra-inputs.json" = {
        text = inputsJsonStr;
        mode = "0600"; # restricted — may contain sensitive config
        description = "Serialized infra module inputs";
        source = "infra";
      };
    }
    // moduleFileEntries;

    # ==========================================================================
    # Devshell environment
    # ==========================================================================
    stackpanel.devshell.env = {
      STACKPANEL_INFRA_INPUTS = "${stateDir}/infra-inputs.json";
    };

    # Gitignore the generated infra package directory
    # stackpanel.gitignore.entries = [ "${outputDir}/" ];

    # Turbo workspace package (generates package.json + turbo.json tasks)
    # ==========================================================================
    stackpanel.turbo.packages.infra = {
      name = cfg.package.name;
      path = outputDir;
      dependencies =
        let
          packageDeps = {
            alchemy = config.stackpanel.deployment.alchemy.version;
          }
          // lib.optionalAttrs config.stackpanel.deployment.alchemy.enable {
            ${config.stackpanel.deployment.alchemy.package.name} = "workspace:*";
          }
          // validatedDeps
          // cfg.package.dependencies;
          invalidCatalogDeps = builtins.attrNames (lib.filterAttrs (_: v: v == "catalog:") packageDeps);
        in
        if invalidCatalogDeps != [ ] then
          builtins.throw "infra package dependencies must declare explicit versions (found catalog: for ${lib.concatStringsSep ", " invalidCatalogDeps})"
        else
          packageDeps;
      devDependencies = {
        bun2nix = "latest";
      };
      exports = {
        "." = {
          default = "./src/index.ts";
        };
        "./*" = {
          default = "./src/*.ts";
        };
      };
      scripts = {
        "alchemy:deploy" = {
          exec = "alchemy deploy";
          turbo = {
            enable = true;
            cache = false;
          };
        };
        "alchemy:destroy" = {
          exec = "alchemy destroy";
          turbo = {
            enable = true;
            cache = false;
          };
        };
        "alchemy:dev" = {
          exec = "alchemy dev";
        };
        postinstall = {
          exec = "test -f bun.lock && bun2nix -o bun.nix || true";
        };
      };
    };

    # ==========================================================================
    # Shell scripts
    # ==========================================================================
    stackpanel.scripts = {
      "infra:new-module" = {
        exec = ''
          MODULE_ID="''${1:?Usage: infra:new-module <module-id>}"

          # Validate module ID
          if ! echo "$MODULE_ID" | grep -qE '^[a-z][a-z0-9-]*$'; then
            echo "Error: Module ID must be lowercase alphanumeric with hyphens (e.g., my-module)"
            exit 1
          fi

          MODULE_DIR="nix/stackpanel/infra/modules/$MODULE_ID"
          if [ -d "$MODULE_DIR" ]; then
            echo "Error: Module directory $MODULE_DIR already exists"
            exit 1
          fi

          MODULE_NAME=$(echo "$MODULE_ID" | sed 's/-/ /g' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)} 1')

          echo "Creating infra module: $MODULE_ID ($MODULE_NAME)"
          mkdir -p "$MODULE_DIR"

          # Generate module.nix
          cat > "$MODULE_DIR/module.nix" << 'NIXEOF'
          # ==============================================================================
          # infra/modules/MODULE_ID/module.nix
          # ==============================================================================
          {
            lib,
            config,
            ...
          }:
          let
            inherit (import ../../../lib/mkInfraModule.nix { inherit lib; }) mkInfraModule;
          in
          mkInfraModule {
            id = "MODULE_ID";
            name = "MODULE_NAME";
            path = ./index.ts;
            inherit config;

            # Module-specific options (beyond enable + sync-outputs which are automatic).
            options = {
              # region = lib.mkOption {
              #   type = lib.types.str;
              #   default = "us-east-1";
              #   description = "AWS region.";
              # };
            };

            # Map Nix config values to TypeScript runtime inputs.
            # Kebab-case keys are auto-converted to camelCase.
            inputs = cfg: {
              # region = cfg.region;
            };

            # NPM packages required by the TypeScript implementation.
            dependencies = {
              # "@aws-sdk/client-s3" = "catalog:";
            };

            # Output declarations. Short form: { key = "description"; }
            # All outputs sync by default. Use { description; sensitive; sync; } for control.
            outputs = {
              # exampleArn = "ARN of the provisioned resource";
            };
          }
          NIXEOF

          # Replace placeholders
          sed -i "" "s/MODULE_ID/$MODULE_ID/g" "$MODULE_DIR/module.nix"
          sed -i "" "s/MODULE_NAME/$MODULE_NAME/g" "$MODULE_DIR/module.nix"

          # Generate index.ts
          cat > "$MODULE_DIR/index.ts" << 'TSEOF'
          // ==============================================================================
          // MODULE_NAME Infra Module
          //
          // Executed by `infra:deploy` via Alchemy.
          // Default export must be Record<string, string> matching module.nix outputs.
          // ==============================================================================
          import Infra from "@stackpanel/infra";

          // ── Params (from module.nix inputs) ────────────────────────────────
          interface Inputs {
            // region: string;
          }

          const infra = new Infra("MODULE_ID");
          const inputs = infra.inputs<Inputs>(
            process.env.STACKPANEL_INFRA_INPUTS_OVERRIDES,
          );

          // ── Resources ──────────────────────────────────────────────────────
          //
          // import { SomeResource } from "@stackpanel/infra/resources/some-resource";
          // const resource = await SomeResource(infra.id("my-resource"), { ... });
          //
          // import { Role } from "alchemy/aws";
          // const role = await Role(infra.id("role"), { roleName: "...", ... });

          // ── Outputs ────────────────────────────────────────────────────────
          export default {
            // exampleArn: resource.arn,
          };
          TSEOF

          sed -i "" "s/MODULE_ID/$MODULE_ID/g" "$MODULE_DIR/index.ts"
          sed -i "" "s/MODULE_NAME/$MODULE_NAME/g" "$MODULE_DIR/index.ts"

          # Trim leading whitespace from heredoc indentation
          sed -i "" 's/^          //' "$MODULE_DIR/module.nix"
          sed -i "" 's/^          //' "$MODULE_DIR/index.ts"

          echo ""
          echo "Created:"
          echo "  $MODULE_DIR/module.nix  — Nix options and module registration"
          echo "  $MODULE_DIR/index.ts    — TypeScript Alchemy implementation"
          echo ""
          echo "Next steps:"
          echo "  1. Add your options to module.nix"
          echo "  2. Implement provisioning logic in index.ts"
          echo "  3. Import the module in nix/stackpanel/infra/default.nix:"
          echo "       ./modules/$MODULE_ID/module.nix"
          echo "  4. Enable in .stack/config.nix:"
          echo "       stackpanel.infra.$MODULE_ID.enable = true;"
          echo "  5. Run: infra:deploy"
        '';
        description = "Scaffold a new infra module";
        args = [
          {
            name = "<module-id>";
            description = "Module identifier (lowercase, hyphens, e.g., my-s3-buckets)";
          }
        ];
      };

      "infra:deploy" = {
        exec = ''
          ${lib.optionalString (config.stackpanel.aws-vault.enable or false) ''
            # Use aws-vault with profile fallback if enabled
            if [ -n "${lib.concatStringsSep " " (config.stackpanel.aws-vault.profiles or [ ])}" ]; then
              echo "Using aws-vault with multi-profile fallback" >&2
              # aws wrapper is already configured with multi-profile support
            fi
          ''}
          cd "${outputDir}" && bunx alchemy deploy "$@"
        '';
        description = "Deploy infrastructure via alchemy (aws-vault integration if enabled)";
        args = [
          {
            name = "--stage";
            description = "Deployment stage (e.g., dev, prod)";
          }
          {
            name = "...";
            description = "Additional alchemy deploy arguments";
          }
        ];
      };

      "infra:destroy" = {
        exec = ''
          ${lib.optionalString (config.stackpanel.aws-vault.enable or false) ''
            # Use aws-vault with profile fallback if enabled
            if [ -n "${lib.concatStringsSep " " (config.stackpanel.aws-vault.profiles or [ ])}" ]; then
              echo "Using aws-vault with multi-profile fallback" >&2
              # aws wrapper is already configured with multi-profile support
            fi
          ''}
          cd "${outputDir}" && bunx alchemy destroy "$@"
        '';
        description = "Destroy infrastructure via alchemy (aws-vault integration if enabled)";
        args = [
          {
            name = "--stage";
            description = "Deployment stage to destroy";
          }
          {
            name = "...";
            description = "Additional alchemy destroy arguments";
          }
        ];
      };

      "infra:dev" = {
        exec = ''
          cd "${outputDir}" && bunx alchemy dev "$@"
        '';
        description = "Start infrastructure dev mode";
        args = [
          {
            name = "...";
            description = "Additional alchemy dev arguments";
          }
        ];
      };

      "infra:pull-outputs" = {
        exec =
          let
            storageType = cfg.storage-backend.type;
            dataDir = config.stackpanel.dirs.data;
            outputsFile = "${dataDir}/infra-outputs.nix";
          in
          if storageType == "chamber" then
            ''
              echo "Pulling outputs from chamber..."
              SERVICE="${cfg.storage-backend.chamber.service}"
              OUTPUT_FILE="${outputsFile}"

              echo "{" > "$OUTPUT_FILE"
              ${lib.concatMapStringsSep "\n" (
                id:
                let
                  mod = cfg.modules.${id};
                  syncKeys = builtins.filter (k: (mod.outputs.${k}.sync or false)) (builtins.attrNames mod.outputs);
                in
                ''
                  echo '  ${id} = {' >> "$OUTPUT_FILE"
                  ${lib.concatMapStringsSep "\n" (
                    key:
                    let
                      formattedKey = builtins.replaceStrings [ "$module" "$key" ] [ id key ] cfg.key-format;
                    in
                    ''
                      VALUE=$(chamber read -q "$SERVICE" "${formattedKey}" 2>/dev/null || echo "")
                      if [ -n "$VALUE" ]; then
                        echo '    ${key} = "'"$VALUE"'";' >> "$OUTPUT_FILE"
                      fi
                    ''
                  ) syncKeys}
                  echo '  };' >> "$OUTPUT_FILE"
                ''
              ) moduleIds}
              echo "}" >> "$OUTPUT_FILE"
              echo "Wrote outputs to $OUTPUT_FILE"
            ''
          else if storageType == "sops" then
            let
              secretsDir = config.stackpanel.secrets.secrets-dir or ".stack/secrets";
              group = cfg.storage-backend.sops.group;
              sopsFile =
                if cfg.storage-backend.sops.group != "" then
                  "${secretsDir}/vars/${group}.sops.yaml"
                else
                  cfg.storage-backend.sops.file-path;
            in
            ''
              echo "Pulling outputs from SOPS..."
              FILE_PATH="${sopsFile}"
              OUTPUT_FILE="${outputsFile}"

              if [ ! -f "$FILE_PATH" ]; then
                echo "SOPS file not found: $FILE_PATH"
                exit 1
              fi

              echo "{" > "$OUTPUT_FILE"
              ${lib.concatMapStringsSep "\n" (
                id:
                let
                  mod = cfg.modules.${id};
                  syncKeys = builtins.filter (k: (mod.outputs.${k}.sync or false)) (builtins.attrNames mod.outputs);
                in
                ''
                  echo '  ${id} = {' >> "$OUTPUT_FILE"
                  ${lib.concatMapStringsSep "\n" (
                    key:
                    let
                      formattedKey = builtins.replaceStrings [ "$module" "$key" ] [ id key ] cfg.key-format;
                    in
                    ''
                                            JSON_PATH='["${formattedKey}"]'
                                            RAW_VALUE=$(sops --extract "$JSON_PATH" "$FILE_PATH" 2>/dev/null || echo "")
                                            if [ -n "$RAW_VALUE" ] && [ "$RAW_VALUE" != "null" ]; then
                                              VALUE=$(printf '%s' "$RAW_VALUE" | python - <<'PY'
                      import json,sys
                      raw = sys.stdin.read().strip()
                      if not raw or raw == "null":
                          sys.exit(0)
                      try:
                          val = json.loads(raw)
                      except Exception:
                          val = raw
                      if val is None:
                          sys.exit(0)
                      if not isinstance(val, str):
                          val = json.dumps(val, separators=(",", ":"))
                      val = val.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n")
                      print(val)
                      PY
                                              )
                                              if [ -n "$VALUE" ]; then
                                                echo '    ${key} = "'"$VALUE"'";' >> "$OUTPUT_FILE"
                                              fi
                                            fi
                    ''
                  ) syncKeys}
                  echo '  };' >> "$OUTPUT_FILE"
                ''
              ) moduleIds}
              echo "}" >> "$OUTPUT_FILE"
              echo "Wrote outputs to $OUTPUT_FILE"
            ''
          else if storageType == "ssm" then
            ''
              echo "Pulling outputs from SSM..."
              PREFIX="${cfg.storage-backend.ssm.prefix}"
              OUTPUT_FILE="${outputsFile}"

              echo "{" > "$OUTPUT_FILE"
              ${lib.concatMapStringsSep "\n" (
                id:
                let
                  mod = cfg.modules.${id};
                  syncKeys = builtins.filter (k: (mod.outputs.${k}.sync or false)) (builtins.attrNames mod.outputs);
                in
                ''
                  echo '  ${id} = {' >> "$OUTPUT_FILE"
                  ${lib.concatMapStringsSep "\n" (
                    key:
                    let
                      formattedKey = builtins.replaceStrings [ "$module" "$key" ] [ id key ] cfg.key-format;
                    in
                    ''
                      VALUE=$(aws ssm get-parameter --name "$PREFIX/${formattedKey}" --with-decryption --query 'Parameter.Value' --output text 2>/dev/null || echo "")
                      if [ -n "$VALUE" ]; then
                        echo '    ${key} = "'"$VALUE"'";' >> "$OUTPUT_FILE"
                      fi
                    ''
                  ) syncKeys}
                  echo '  };' >> "$OUTPUT_FILE"
                ''
              ) moduleIds}
              echo "}" >> "$OUTPUT_FILE"
              echo "Wrote outputs to $OUTPUT_FILE"
            ''
          else
            ''
              echo "Storage backend '${storageType}' does not support pull-outputs."
              echo "Supported backends: chamber, sops, ssm"
              exit 1
            '';
        description = "Pull infra outputs from storage backend into .stack/data/infra-outputs.nix";
      };
    };

    # ==========================================================================
    # Stackpanel module registration
    # ==========================================================================
    stackpanel.modules.infra = {
      enable = true;
      meta = {
        name = "Infrastructure";
        description = "Alchemy-based infrastructure provisioning with pluggable output storage";
        icon = "server";
        category = "infrastructure";
        author = "Stackpanel";
        version = "1.0.0";
      };
      source.type = "builtin";
      features = {
        files = true;
        scripts = true;
        packages = false;
        healthchecks = false;
        services = false;
        secrets = false;
        tasks = false;
        appModule = false;
      };
      tags = [
        "infrastructure"
        "alchemy"
        "iac"
      ];
      priority = 15; # Load early — other modules may depend on infra outputs
    };

    # ==========================================================================
    # MOTD
    # ==========================================================================
    stackpanel.motd.commands = [
      {
        name = "infra:deploy";
        description = "Deploy infrastructure";
      }
      {
        name = "infra:pull-outputs";
        description = "Pull outputs from ${cfg.storage-backend.type}";
      }
    ];

    stackpanel.motd.features = [
      "Infrastructure (${cfg.framework})"
    ]
    ++ lib.optional (cfg.storage-backend.type != "none") "Output sync (${cfg.storage-backend.type})"
    ++ lib.optional (cfg.package.bun-nix != null || allModulesHaveBunDeps) "Deps validated (bun2nix)";

    # ==========================================================================
    # Agent serialization
    # ==========================================================================
    stackpanel.serializable.infra = {
      inherit (cfg) enable framework key-format;
      output-dir = cfg.output-dir;
      storage-backend = {
        inherit (cfg.storage-backend) type;
      }
      // lib.optionalAttrs (cfg.storage-backend.type == "chamber") {
        service = cfg.storage-backend.chamber.service;
      }
      // lib.optionalAttrs (cfg.storage-backend.type == "sops") {
        file-path = storageBackendConfig.filePath;
        group = cfg.storage-backend.sops.group;
      }
      // lib.optionalAttrs (cfg.storage-backend.type == "ssm") {
        prefix = cfg.storage-backend.ssm.prefix;
      };
      modules = lib.mapAttrs (_id: mod: {
        inherit (mod) name description;
        outputs = lib.mapAttrs (_k: v: {
          inherit (v) description sensitive sync;
        }) mod.outputs;
      }) cfg.modules;
    };
  };
}
