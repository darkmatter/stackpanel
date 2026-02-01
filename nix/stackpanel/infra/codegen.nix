# ==============================================================================
# infra/codegen.nix
#
# Code generation engine for the infrastructure module system.
#
# Generates via stackpanel.files.entries:
#   - src/index.ts       (Infra class with embedded project config)
#   - src/types.ts       (per-module input TypeScript interfaces)
#   - src/resources/*.ts  (custom alchemy resources: KMS Key, KMS Alias)
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
      {
        type = "sops";
        filePath = cfg.storage-backend.sops.file-path;
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
        fields = lib.mapAttrsToList (k: v: "  ${k}: ${nixTypeToTs v};") value;
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
  infraTemplate = builtins.readFile ./templates/infra.tmpl.ts;
  infraClassTs =
    builtins.replaceStrings [ "{{PROJECT_CONFIG}}" ] [ (builtins.toJSON inputsJson.__config__) ]
      infraTemplate;

  # Static resource files (no substitution needed)
  kmsKeyTs = builtins.readFile ./templates/kms-key.ts;
  kmsAliasTs = builtins.readFile ./templates/kms-alias.ts;

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
  # ============================================================================
  alchemyRunTs =
    let
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
          }Outputs = (await import("./modules/${id}.ts")).default;
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
    in
    ''
      // Generated by stackpanel — do not edit manually.
      import alchemy from "alchemy";
      import Infra from "./src/index.ts";

      const app = await alchemy("${projectName}-infra", {
        password: process.env.ALCHEMY_PASSWORD ?? "local-dev-password",
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
  moduleFileEntries = lib.mapAttrs' (
    id: mod:
    lib.nameValuePair "${outputDir}/modules/${id}.ts" {
      text = builtins.readFile mod.path;
      mode = "0644";
      description = "Infra module: ${mod.name}";
      source = "infra";
    }
  ) cfg.modules;

in
{
  config = lib.mkIf cfg.enable {
    # ==========================================================================
    # File generation
    # ==========================================================================
    stackpanel.files.entries = {
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
      "${outputDir}/src/resources/kms-key.ts" = {
        text = kmsKeyTs;
        mode = "0644";
        description = "Custom KMS Key alchemy resource";
        source = "infra";
      };

      "${outputDir}/src/resources/kms-alias.ts" = {
        text = kmsAliasTs;
        mode = "0644";
        description = "Custom KMS Alias alchemy resource";
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

    # ==========================================================================
    # Turbo workspace package (generates package.json + turbo.json tasks)
    # ==========================================================================
    stackpanel.turbo.packages.infra = {
      name = cfg.package.name;
      path = outputDir;
      dependencies = {
        alchemy = "catalog:";
      }
      // allDeps
      // cfg.package.dependencies;
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
      "infra:deploy" = {
        exec = ''
          cd "${outputDir}" && bunx alchemy deploy "$@"
        '';
        description = "Deploy infrastructure via alchemy";
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
          cd "${outputDir}" && bunx alchemy destroy "$@"
        '';
        description = "Destroy infrastructure via alchemy";
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
              echo "Supported backends: chamber, ssm"
              exit 1
            '';
        description = "Pull infra outputs from storage backend into .stackpanel/data/infra-outputs.nix";
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
        file-path = cfg.storage-backend.sops.file-path;
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
