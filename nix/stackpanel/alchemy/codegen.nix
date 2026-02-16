# ==============================================================================
# alchemy/codegen.nix
#
# Code generation engine for the @gen/alchemy shared package.
#
# Generates via stackpanel.files.entries:
#   - src/index.ts       (createApp factory, re-exports)
#   - src/state-store.ts (state store provider factory)
#   - src/helpers.ts     (shared utilities: SSM, bindings, port computation)
#   - package.json       (via turbo.packages)
#   - tsconfig.json
#
# Also:
#   - Registers .alchemy in .gitignore
#   - Sets ALCHEMY_STATE_TOKEN env var if sopsPath is configured
#   - Registers as a stackpanel module for UI
#   - Serializes config for the agent
# ==============================================================================
{
  lib,
  config,
  ...
}:
let
  cfg = config.stackpanel.alchemy;
  outputDir = cfg.package.output-dir;

  # ============================================================================
  # Template processing: src/index.ts
  # ============================================================================
  indexTemplate = builtins.readFile ./templates/index.tmpl.ts;
  indexTs = builtins.replaceStrings
    [
      "__APP_NAME__"
      "__STATE_STORE_PROVIDER__"
      "__CF_API_TOKEN_ENV_VAR__"
    ]
    [
      cfg.appName
      cfg.stateStore.provider
      cfg.stateStore.cloudflare.apiTokenEnvVar
    ]
    indexTemplate;

  # ============================================================================
  # Template processing: src/state-store.ts
  # ============================================================================
  stateStoreTs = builtins.readFile ./templates/state-store.tmpl.ts;

  # ============================================================================
  # Template processing: src/helpers.ts
  #
  # Conditionally includes helper functions based on cfg.helpers.*
  # ============================================================================
  helpersTemplate = builtins.readFile ./templates/helpers.tmpl.ts;

  ssmHelper =
    if cfg.helpers.ssm then
      ''
        /**
         * Read a secret value from AWS SSM Parameter Store.
         *
         * Useful for retrieving pre-populated API keys and credentials
         * during alchemy provisioning.
         *
         * @param name - SSM parameter name (e.g. "/common/neon-api-key")
         * @returns The decrypted parameter value
         * @throws If the parameter is not found or empty
         *
         * @example
         * ```ts
         * const apiKey = await getSSMSecret("/common/neon-api-key");
         * ```
         */
        export async function getSSMSecret(name: string): Promise<string> {
          const { SSMClient, GetParameterCommand } = await import(
            "@aws-sdk/client-ssm"
          );
          const client = new SSMClient({});
          const response = await client.send(
            new GetParameterCommand({ Name: name, WithDecryption: true }),
          );
          if (!response.Parameter?.Value) {
            throw new Error(`SSM Parameter ''${name} not found or empty`);
          }
          return response.Parameter.Value;
        }
      ''
    else
      "";

  bindingsHelper =
    if cfg.helpers.bindings then
      ''
        /**
         * Resolve environment variable bindings, wrapping secrets with alchemy.secret().
         *
         * Reads values from process.env and wraps those in the secretNames set
         * with alchemy.secret() for safe handling in Cloudflare Workers bindings.
         *
         * @param bindingNames - All env var names to include
         * @param secretNames - Subset of bindingNames that contain sensitive values
         * @returns Object with resolved values (secrets wrapped, others plain)
         *
         * @example
         * ```ts
         * const bindings = resolveBindings(
         *   ["DATABASE_URL", "CORS_ORIGIN", "API_KEY"],
         *   ["DATABASE_URL", "API_KEY"],
         * );
         * // { DATABASE_URL: Secret<...>, CORS_ORIGIN: "https://...", API_KEY: Secret<...> }
         * ```
         */
        export function resolveBindings(
          bindingNames: string[],
          secretNames: string[],
        ): Record<string, unknown> {
          const secretSet = new Set(secretNames);
          const resolved: Record<string, unknown> = {};
          for (const key of bindingNames) {
            const value = process.env[key];
            resolved[key] = secretSet.has(key)
              ? alchemy.secret(value ?? "")
              : (value ?? "");
          }
          return resolved;
        }
      ''
    else
      "";

  computePortHelper =
    if cfg.helpers.computePort then
      ''
        /**
         * Compute a stable port from a project name.
         *
         * Mirrors the Nix mkProjectPort function to produce the same port
         * from the same project name across Nix and TypeScript.
         *
         * @param name - Project name to hash
         * @param minPort - Minimum port number (default: 3000)
         * @param portRange - Port range size (default: 7000)
         * @returns Deterministic port number in [minPort, minPort + portRange)
         *
         * @example
         * ```ts
         * const port = computeProjectPort("my-project"); // e.g. 5342
         * ```
         */
        export function computeProjectPort(
          name: string,
          minPort = 3000,
          portRange = 7000,
        ): number {
          const { createHash } = require("node:crypto");
          const hash = createHash("md5").update(name).digest("hex");
          const portOffset = Number.parseInt(hash.substring(0, 4), 16);
          return minPort + (portOffset % portRange);
        }
      ''
    else
      "";

  # Build the helpers imports line (only crypto if computePort is enabled)
  helperImports =
    if cfg.helpers.computePort then
      ""
    else
      "";

  helpersTs = builtins.replaceStrings
    [
      "__HELPER_IMPORTS__"
      "__SSM_HELPER__"
      "__BINDINGS_HELPER__"
      "__COMPUTE_PORT_HELPER__"
    ]
    [
      helperImports
      ssmHelper
      bindingsHelper
      computePortHelper
    ]
    helpersTemplate;

  # ============================================================================
  # tsconfig.json
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
    include = [ "src/**/*.ts" ];
    exclude = [
      "node_modules"
      "dist"
    ];
  };

  # ============================================================================
  # Determine dependencies based on enabled helpers
  # ============================================================================
  baseDeps = {
    alchemy = "catalog:";
  };

  helperDeps =
    lib.optionalAttrs cfg.helpers.ssm {
      "@aws-sdk/client-ssm" = "catalog:";
    };

  allDeps = baseDeps // helperDeps // cfg.package.extra-dependencies;

in
{
  config = lib.mkIf cfg.enable {
    # ==========================================================================
    # File generation
    # ==========================================================================
    stackpanel.files.entries = {
      # Main entry: createApp factory + re-exports
      "${outputDir}/src/index.ts" = {
        text = indexTs;
        mode = "0644";
        description = "Alchemy app factory and re-exports (@gen/alchemy)";
        source = "alchemy";
      };

      # State store provider factory
      "${outputDir}/src/state-store.ts" = {
        text = stateStoreTs;
        mode = "0644";
        description = "Alchemy state store provider factory";
        source = "alchemy";
      };

      # Shared helpers
      "${outputDir}/src/helpers.ts" = {
        text = helpersTs;
        mode = "0644";
        description = "Shared alchemy helpers (SSM, bindings, port)";
        source = "alchemy";
      };

      # TSConfig
      "${outputDir}/tsconfig.json" = {
        type = "json";
        jsonValue = tsconfigJsonValue;
        mode = "0644";
        description = "TypeScript configuration for @gen/alchemy";
        source = "alchemy";
      };
    };

    # ==========================================================================
    # Turbo workspace package (generates package.json)
    # ==========================================================================
    stackpanel.turbo.packages.alchemy = {
      name = cfg.package.name;
      path = outputDir;
      dependencies = allDeps;
      exports = {
        "." = {
          default = "./src/index.ts";
        };
        "./*" = {
          default = "./src/*.ts";
        };
      } // cfg.package.extra-exports;
    };

    # ==========================================================================
    # .gitignore entries
    # ==========================================================================
    stackpanel.files.entries.".gitignore".lines = [
      ".alchemy"
    ];

    # ==========================================================================
    # Devshell environment
    # ==========================================================================
    stackpanel.devshell.env = lib.optionalAttrs (cfg.secrets.stateTokenSopsPath != null) {
      ${cfg.secrets.stateTokenEnvVar} = cfg.secrets.stateTokenSopsPath;
    };

    # ==========================================================================
    # Stackpanel module registration
    # ==========================================================================
    stackpanel.modules.alchemy = {
      enable = true;
      meta = {
        name = "Alchemy";
        description = "Shared Alchemy IaC configuration and helpers (@gen/alchemy)";
        icon = "flask-conical";
        category = "infrastructure";
        author = "Stackpanel";
        version = "1.0.0";
      };
      source.type = "builtin";
      features = {
        files = true;
        scripts = false;
        packages = false;
        healthchecks = false;
        services = false;
        secrets = cfg.secrets.stateTokenSopsPath != null;
        tasks = false;
        appModule = false;
      };
      tags = [
        "infrastructure"
        "alchemy"
        "iac"
        "codegen"
      ];
      priority = 10; # Load very early -- other modules depend on alchemy config
    };

    # ==========================================================================
    # Agent serialization
    # ==========================================================================
    stackpanel.serializable.alchemy = {
      inherit (cfg) enable version appName stage;
      stateStore = {
        inherit (cfg.stateStore) provider;
      };
      package = {
        inherit (cfg.package) name output-dir;
      };
      helpers = {
        inherit (cfg.helpers) ssm bindings computePort;
      };
    };
  };
}
