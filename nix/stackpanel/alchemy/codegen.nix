# ==============================================================================
# alchemy/codegen.nix
#
# Code generation engine for the @gen/alchemy shared package.
#
# Generates via stackpanel.files.entries:
#   - src/index.ts       (createApp factory, re-exports)
#   - src/state-store.ts (state store provider factory)
#   - src/helpers.ts     (shared utilities: SSM, bindings, port computation)
#   - bootstrap.run.ts   (state store bootstrap, if deploy enabled)
#   - package.json       (via turbo.packages)
#   - tsconfig.json
#
# Also:
#   - Registers .alchemy in .gitignore
#   - Sets ALCHEMY_STATE_TOKEN + CLOUDFLARE_API_TOKEN env vars if sops-path configured
#   - Registers alchemy:setup and deploy scripts (if deploy enabled)
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
  deployCfg = cfg.deploy;
  outputDir = cfg.package.output-dir;

  # ============================================================================
  # Template processing: src/index.ts
  # ============================================================================
  indexTemplate = builtins.readFile ./templates/index.tmpl.ts;
  indexTs =
    builtins.replaceStrings
      [
        "__APP_NAME__"
        "__STATE_STORE_PROVIDER__"
        "__CF_API_TOKEN_ENV_VAR__"
      ]
      [
        cfg.app-name
        cfg.state-store.provider
        cfg.state-store.cloudflare.api-token-env-var
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
    if cfg.helpers.compute-port then
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

  # Build the helpers imports line (only crypto if compute-port is enabled)
  helperImports = if cfg.helpers.compute-port then "" else "";

  helpersTs =
    builtins.replaceStrings
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
  # Template processing: bootstrap.run.ts (deploy)
  # ============================================================================
  bootstrapTemplate = builtins.readFile ./templates/bootstrap.tmpl.ts;
  bootstrapTs =
    builtins.replaceStrings
      [
        "__APP_NAME__"
        "__CF_API_TOKEN_ENV_VAR__"
        "__STATE_TOKEN_ENV_VAR__"
      ]
      [
        cfg.app-name
        cfg.secrets.cloudflare-token-env-var
        cfg.secrets.state-token-env-var
      ]
      bootstrapTemplate;

  bootstrapFile = "${outputDir}/bootstrap.run.ts";

  # ============================================================================
  # Template processing: setup script (deploy)
  # ============================================================================
  setupTemplate = builtins.readFile ./templates/setup.tmpl.sh;
  setupSh =
    builtins.replaceStrings
      [
        "__APP_NAME__"
        "__SOPS_GROUP__"
        "__CF_TOKEN_ENV_VAR__"
        "__STATE_TOKEN_ENV_VAR__"
        "__TOKEN_SCOPES__"
        "__AUTO_PROVISION__"
        "__BOOTSTRAP_FILE__"
      ]
      [
        cfg.app-name
        cfg.secrets.sops-group
        cfg.secrets.cloudflare-token-env-var
        cfg.secrets.state-token-env-var
        deployCfg.token-scopes
        (if deployCfg.auto-provision-state-store then "true" else "false")
        bootstrapFile
      ]
      setupTemplate;

  # ============================================================================
  # Template processing: deploy wrapper (deploy)
  # ============================================================================
  deployTemplate = builtins.readFile ./templates/deploy.tmpl.sh;
  deploySh =
    builtins.replaceStrings
      [
        "__CF_TOKEN_ENV_VAR__"
        "__STATE_TOKEN_ENV_VAR__"
        "__ALCHEMY_RUN_FILE__"
        "__STATE_PROVIDER__"
      ]
      [
        cfg.secrets.cloudflare-token-env-var
        cfg.secrets.state-token-env-var
        deployCfg.run-file
        cfg.state-store.provider
      ]
      deployTemplate;

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

  helperDeps = lib.optionalAttrs cfg.helpers.ssm {
    "@aws-sdk/client-ssm" = "catalog:";
  };

  allDeps = baseDeps // helperDeps // cfg.package.extra-dependencies;

  # ============================================================================
  # Flags for conditional features
  # ============================================================================
  hasSecrets =
    cfg.secrets.state-token-sops-path != null || cfg.secrets.cloudflare-token-sops-path != null;

in
{
  config = lib.mkIf cfg.enable {
    # ==========================================================================
    # Bun catalog — register actual versions for "catalog:" references
    # ==========================================================================
    stackpanel.bun.catalog = {
      alchemy = cfg.version;
    } // lib.optionalAttrs cfg.helpers.ssm {
      "@aws-sdk/client-ssm" = "^3.953.0";
    };

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

      # .gitignore
      ".gitignore".lines = [
        ".alchemy"
      ];
    }
    # Bootstrap file (generated when deploy is enabled with auto-provision)
    // lib.optionalAttrs (deployCfg.enable && deployCfg.auto-provision-state-store) {
      "${bootstrapFile}" = {
        text = bootstrapTs;
        mode = "0644";
        description = "Alchemy state store bootstrap (uses filesystem state to provision CF worker)";
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
      }
      // cfg.package.extra-exports;
    };

    # ==========================================================================
    # Devshell environment
    #
    # Wire SOPS-stored tokens to env vars so they're auto-loaded on shell entry.
    # ==========================================================================
    stackpanel.devshell.env =
      lib.optionalAttrs (cfg.secrets.state-token-sops-path != null) {
        ${cfg.secrets.state-token-env-var} = cfg.secrets.state-token-sops-path;
      }
      // lib.optionalAttrs (cfg.secrets.cloudflare-token-sops-path != null) {
        ${cfg.secrets.cloudflare-token-env-var} = cfg.secrets.cloudflare-token-sops-path;
      };

    # ==========================================================================
    # Deploy scripts
    # ==========================================================================
    stackpanel.scripts = lib.mkIf deployCfg.enable {
      "alchemy:setup" = {
        exec = setupSh;
        description = "One-time Cloudflare deployment setup (OAuth, token creation, secrets)";
        args = [
          {
            name = "--force";
            description = "Re-run setup even if tokens already exist";
          }
          {
            name = "--skip-secrets";
            description = "Print tokens to stdout instead of storing in SOPS";
          }
        ];
      };

      "deploy" = {
        exec = deploySh;
        description = "Deploy via alchemy (auto-runs setup if Cloudflare is not configured)";
        args = [
          {
            name = "stage";
            description = "Deployment stage (default: $USER)";
          }
          {
            name = "...";
            description = "Additional alchemy deploy arguments (after --)";
          }
        ];
      };
    };

    # ==========================================================================
    # MOTD
    # ==========================================================================
    stackpanel.motd.commands = lib.mkIf deployCfg.enable [
      {
        name = "deploy <stage>";
        description = "Deploy to Cloudflare";
      }
      {
        name = "alchemy:setup";
        description = "Configure Cloudflare tokens";
      }
    ];

    stackpanel.motd.features = [ "Alchemy IaC" ] ++ lib.optional deployCfg.enable "Cloudflare deploy";

    # ==========================================================================
    # Stackpanel module registration
    # ==========================================================================
    stackpanel.modules.alchemy = {
      enable = true;
      meta = {
        name = "Alchemy";
        description = "Shared Alchemy IaC configuration, deploy scripts, and helpers (@gen/alchemy)";
        icon = "flask-conical";
        category = "infrastructure";
        author = "Stackpanel";
        version = "1.0.0";
      };
      source.type = "builtin";
      features = {
        files = true;
        scripts = deployCfg.enable;
        packages = false;
        healthchecks = false;
        services = false;
        secrets = hasSecrets;
        tasks = false;
        appModule = false;
      };
      tags = [
        "infrastructure"
        "alchemy"
        "iac"
        "codegen"
        "cloudflare"
        "deploy"
      ];
      priority = 10; # Load very early -- other modules depend on alchemy config
    };

    # ==========================================================================
    # Agent serialization
    # ==========================================================================
    stackpanel.serializable.alchemy = {
      inherit (cfg)
        enable
        version
        app-name
        stage
        ;
      state-store = {
        inherit (cfg.state-store) provider;
      };
      package = {
        inherit (cfg.package) name output-dir;
      };
      helpers = {
        inherit (cfg.helpers) ssm bindings compute-port;
      };
      deploy = {
        inherit (deployCfg)
          enable
          token-scopes
          run-file
          auto-provision-state-store
          ;
      };
      secrets = {
        inherit (cfg.secrets) sops-group;
        has-cloudflare-token = cfg.secrets.cloudflare-token-sops-path != null;
        has-state-token = cfg.secrets.state-token-sops-path != null;
      };
    };
  };
}
