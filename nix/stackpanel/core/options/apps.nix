# ==============================================================================
# apps.nix
#
# Application configuration options - stable ports, local domains, tooling, and Caddy virtual hosts.
#
# Manages application ports and Caddy virtual hosts in a unified way.
# Each app gets a deterministic port and optionally a domain for Caddy vhosts.
#
# Port Layout:
#   App ports are computed by hashing the repo key and app key.
#   `offset` is preserved for legacy callers and display metadata, but the active
#   stable-port path does not derive the port from basePort + offset.
#
# Domain Format:
#   Virtual hosts use the format: <app>.<project>.<tld>
#   Example: web.myproject.localhost, api.myproject.lan
#   The TLD is configured via stackpanel.caddy.tld (default: "localhost")
#
# Options per app:
#   - offset: Legacy display/compat metadata for old basePort + offset layouts
#   - domain: App subdomain label for vhost (null = no vhost). Creates <domain>.<project>.<tld>
#   - tls: Use https URL scheme for the vhost; local certs require Step CA/Caddy TLS setup
#
# Usage:
#   stackpanel.apps = {
#     web = { path = "apps/web"; };      # Port only, no vhost
#     server = { offset = 1; };          # Legacy offset metadata
#     docs = { domain = "docs"; };       # Port + docs.<project>.localhost vhost
#     api = { domain = "api"; tls = true; };  # TLS vhost
#   };
#
# Access computed values:
#   config.stackpanel.appsComputed.<name>.port
#   config.stackpanel.appsComputed.<name>.url
#
# Note: pkgs is optional. When not available (e.g., flake-parts top-level),
# wrappedTooling will be null. Full computation happens when pkgs is provided.
# ==============================================================================
{
  lib,
  config,
  pkgs ? null,
  ...
}:
let
  # pkgs is optional - provided by devenv/flakeModule via _module.args
  # or passed directly in specialArgs
  hasPkgs = pkgs != null;

  # Get user-defined apps (before computed values)
  rawApps = config.stackpanel.apps;
  portsCfg = config.stackpanel.ports;
  caddyCfg = config.stackpanel.caddy;
  repoKey = rawApps.github or "darkmatter/stackpanel";

  # Domain format: <app>.<project>.<tld>
  projectName = portsCfg.project-name;
  tld = caddyCfg.tld or "localhost";
  portsLib = import ../../lib/ports.nix { inherit lib; };
  db = import ../../db { inherit lib; };

  # Tool step submodule - defines schema for tooling configuration
  toolStepModule =
    { lib, ... }:
    {
      options = {
        package = lib.mkOption {
          type = lib.types.package;
          description = "Package that provides the tool binary.";
        };
        bin = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Optional executable name when the package exposes more than one binary.";
          example = "npm";
        };
        args = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Arguments passed to the tool binary in order.";
          example = [ "run" "build" ];
        };
        env = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { };
          description = "Environment variables set before running this tooling step.";
          example = { NODE_ENV = "production"; };
        };
        configPath = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Repo-relative config file path passed to the tool when configArg is set or omitted.";
          example = "apps/web/vite.config.ts";
        };
        configArg = lib.mkOption {
          type = lib.types.nullOr (lib.types.listOf lib.types.str);
          default = null;
          description = "Argument prefix inserted before configPath, such as `--config` or `-c`.";
          example = [ "--config" ];
        };
        cwd = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Repo-relative working directory for the tooling step; defaults to the app path.";
          example = "apps/web";
        };
      };
    };

  # Nix-specific app options (not in proto schema)
  # These are runtime/devenv options that don't belong in serialized data
  # Note: port and domain are defined in the proto schema (db.extend.app)
  nixAppOptionsModule =
    { lib, config, ... }:
    {
      options = {
        framework = {
          tanstack-start = {
            enable = lib.mkEnableOption "TanStack Start (full-stack SSR with TanStack Router + Nitro)";
          };

          nextjs = {
            enable = lib.mkEnableOption "Next.js (App Router or Pages)";
            output = lib.mkOption {
              type = lib.types.enum [
                "standalone"
                "export"
              ];
              default = "standalone";
              description = "Next.js output mode passed through to generated deployment/tooling metadata.";
              example = "standalone";
            };
          };

          vite = {
            enable = lib.mkEnableOption "Vite SPA (React, Vue, Svelte, etc.)";
            ssr = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Whether this Vite app uses server-side rendering instead of static SPA output.";
              example = true;
            };
            assets-dir = lib.mkOption {
              type = lib.types.str;
              default = "dist";
              description = "Directory, relative to the app path, where Vite writes built assets.";
              example = "dist/client";
            };
          };

          hono = {
            enable = lib.mkEnableOption "Hono API server";
            entrypoint = lib.mkOption {
              type = lib.types.str;
              default = "src/index.ts";
              description = "Entrypoint file for the Hono worker.";
            };
          };

          astro = {
            enable = lib.mkEnableOption "Astro (static/SSR)";
          };

          remix = {
            enable = lib.mkEnableOption "Remix";
          };

          nuxt = {
            enable = lib.mkEnableOption "Nuxt";
          };
        };

        deployment = {
          enable = lib.mkEnableOption "deployment for this app";

          host = lib.mkOption {
            type = lib.types.nullOr (
              lib.types.enum [
                "cloudflare"
                "fly"
                "vercel"
                "aws"
              ]
            );
            default = null;
            description = ''
              Deployment host/platform. Combined with `framework` to determine
              the alchemy resource type:

                framework × host → alchemy resource
                tanstack-start × cloudflare → TanStackStart
                nextjs × cloudflare → Nextjs
                vite × cloudflare → cloudflare.Vite
                hono × cloudflare → cloudflare.Worker
                * × fly → Fly container
            '';
            example = "cloudflare";
          };

          bindings = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = ''
              Environment variable names to bind to the deployed app.
              Each name is read from `process.env` at deploy time.

              When empty (default), auto-derived from env var names across
              all `environments`. Set explicitly only when deploy-time names
              differ from development names (e.g., DATABASE_URL vs POSTGRES_URL).
            '';
            example = [
              "DATABASE_URL"
              "CORS_ORIGIN"
              "BETTER_AUTH_SECRET"
            ];
          };

          secrets = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = ''
              Subset of `bindings` that contain sensitive values.
              These are wrapped with `alchemy.secret()` at deploy time.

              When empty (default), auto-derived from `secrets` lists in
              each environment under `environments`. Set explicitly to override.
            '';
            example = [
              "DATABASE_URL"
              "BETTER_AUTH_SECRET"
            ];
          };
        };

        tooling = {
          install = lib.mkOption {
            type = lib.types.nullOr (lib.types.submodule toolStepModule);
            default = null;
            description = "Tool wrapper used to install this app's dependencies.";
          };
          build = lib.mkOption {
            type = lib.types.nullOr (lib.types.submodule toolStepModule);
            default = null;
            description = "Tool wrapper used to build this app.";
          };
          test = lib.mkOption {
            type = lib.types.nullOr (lib.types.submodule toolStepModule);
            default = null;
            description = "Tool wrapper used to run this app's tests.";
          };
          dev = lib.mkOption {
            type = lib.types.nullOr (lib.types.submodule toolStepModule);
            default = null;
            description = "Tool wrapper used to start this app in development mode.";
          };
          build-steps = lib.mkOption {
            type = lib.types.listOf (lib.types.submodule toolStepModule);
            default = [ ];
            description = "Additional ordered tool wrappers to run as part of this app's build.";
          };
          formatters = lib.mkOption {
            type = lib.types.listOf (lib.types.submodule toolStepModule);
            default = [ ];
            description = "Tool wrappers that format this app's source files.";
          };
          linters = lib.mkOption {
            type = lib.types.listOf (lib.types.submodule toolStepModule);
            default = [ ];
            description = "Tool wrappers that lint this app's source files.";
          };
        };
        offset = lib.mkOption {
          description = ''
            Legacy app offset metadata for older `basePort + offset` layouts.

            The current computed port path hashes the repo key and app key, so this
            value is preserved in `appsComputed.<name>.offset` but does not change
            `appsComputed.<name>.port`. Prefer renaming the app key or setting the
            proto-derived `port` field when a fixed external port is needed.
          '';
          type = lib.types.nullOr lib.types.int;
          default = null;
          example = 5;
        };
        tls = lib.mkOption {
          description = ''
            Use HTTPS for the app URL when `domain` is set.

            This changes `appsComputed.<name>.url` from `http://...` to
            `https://...`. Local certificate issuance still depends on the Caddy
            and Step CA TLS modules being configured for the project.
          '';
          type = lib.types.bool;
          default = false;
        };
        packageName = lib.mkOption {
          description = ''
            NPM package name for turbo filter (e.g., "@stackpanel/web").
            If null, defaults to the app name.
          '';
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "@myorg/web";
        };
      };

      # =========================================================================
      # Auto-derive deployment.bindings and deployment.secrets from
      # the unified `env` field (map<string, EnvironmentVariable>).
      #
      # bindings = all env var names declared under `env`
      # secrets  = subset of bindings considered sensitive: either
      #   `secret = true` is set explicitly, or a `sops` reference is provided.
      #
      # Uses mkDefault so explicit user values take precedence.
      # =========================================================================
      config =
        let
          envVars = config.env or { };
          allEnvNames = lib.attrNames envVars;
          isSecret = m: (m.secret or false) || ((m.sops or null) != null && (m.sops or "") != "");
          allSecretNames = lib.attrNames (lib.filterAttrs (_: isSecret) envVars);
        in
        {
          deployment.bindings = lib.mkDefault allEnvNames;
          deployment.secrets = lib.mkDefault allSecretNames;
        };
    };

  # ===========================================================================
  # Tool wrapper generation (requires pkgs)
  # Only define these functions when pkgs is available to avoid evaluation errors
  # ===========================================================================
  mkToolWrapper =
    if !hasPkgs then
      null
    else
      appName: appCfg: label: stepCfg:
      let
        exe =
          if stepCfg.bin != null then "${stepCfg.package}/bin/${stepCfg.bin}" else lib.getExe stepCfg.package;
        appPath = stepCfg.cwd or appCfg.path or null;
        args = lib.escapeShellArgs stepCfg.args;
        configArgs =
          if stepCfg.configPath == null then
            ""
          else if stepCfg.configArg == null then
            ''"$ROOT/${stepCfg.configPath}"''
          else
            ''${lib.escapeShellArgs stepCfg.configArg} "$ROOT/${stepCfg.configPath}"'';
        envLines = lib.concatMapStringsSep "\n" (
          name:
          let
            value = stepCfg.env.${name};
          in
          "export ${name}=${lib.escapeShellArg value}"
        ) (lib.attrNames stepCfg.env);
        cdLine = if appPath != null then ''cd "$ROOT/${appPath}"'' else "";
      in
      pkgs.writeShellApplication {
        name = "${appName}-${label}";
        runtimeInputs = [ stepCfg.package ];
        text = lib.concatStringsSep "\n" [
          "set -euo pipefail"
          ''ROOT="''${STACKPANEL_ROOT:-$(pwd)}"''
          envLines
          cdLine
          "exec ${exe} ${args} ${configArgs}"
        ];
      };

  wrapToolList =
    if mkToolWrapper == null then
      null
    else
      appName: appCfg: label: tools:
      lib.imap0 (idx: step: mkToolWrapper appName appCfg "${label}-${toString idx}" step) tools;

  # ===========================================================================
  # Computed app configurations
  # ===========================================================================
  appNames = lib.attrNames rawApps;

  # Compute wrappedTooling for a single app (only when pkgs available)
  mkWrappedTooling =
    if mkToolWrapper == null then
      null
    else
      name: appCfg:
      let
        inherit (appCfg) tooling;
      in
      {
        install =
          if tooling.install != null then mkToolWrapper name appCfg "install" tooling.install else null;
        build = if tooling.build != null then mkToolWrapper name appCfg "build" tooling.build else null;
        test = if tooling.test != null then mkToolWrapper name appCfg "test" tooling.test else null;
        dev = if tooling.dev != null then mkToolWrapper name appCfg "dev" tooling.dev else null;
        build-steps = wrapToolList name appCfg "build" tooling.build-steps;
        formatters = wrapToolList name appCfg "format" tooling.formatters;
        linters = wrapToolList name appCfg "lint" tooling.linters;
      };

  # Compute full app configurations with ports
  computedApps = lib.listToAttrs (
    lib.imap0 (
      idx: name:
      let
        appCfg = rawApps.${name};
        offset = if appCfg.offset != null then appCfg.offset else idx;
        port = portsLib.stablePort {
          repo = repoKey;
          service = name;
        };
        # Domain format: <app>.<project>.<tld> (e.g., web.myproject.localhost)
        domain = if appCfg.domain != null then "${appCfg.domain}.${projectName}.${tld}" else null;
        protocol = if appCfg.tls then "https" else "http";
        url = if domain != null then "${protocol}://${domain}" else null;
        inherit (appCfg) tooling;
        # Only compute wrappedTooling when pkgs is available
        wrappedTooling = if mkWrappedTooling != null then mkWrappedTooling name appCfg else null;
        deployTargets = if appCfg.deploy.enable then appCfg.deploy.targets else [ ];

        # Framework mutual exclusivity check
        _frameworkNames = [
          "tanstack-start"
          "nextjs"
          "vite"
          "hono"
          "astro"
          "remix"
          "nuxt"
        ];
        _enabledFrameworks = lib.filter (fw: appCfg.framework.${fw}.enable or false) _frameworkNames;
      in
      assert lib.assertMsg (lib.length _enabledFrameworks <= 1)
        "stackpanel.apps.${name}: at most one framework may be enabled, but found ${toString (lib.length _enabledFrameworks)}: ${lib.concatStringsSep ", " _enabledFrameworks}";
      {
        inherit name;
        value = {
          inherit
            port
            domain
            url
            tooling
            wrappedTooling
            deployTargets
            ;
          inherit (appCfg) tls offset;

          # Build metadata (serializable for UI)
          # An app is buildable if build.enable is set or a language module provides a package
          build =
            let
              goPackages = config.stackpanel.go.packages.apps or { };
              bunPackages = config.stackpanel.bun.packages.apps or { };
              hasLangPackage = goPackages ? ${name} || bunPackages ? ${name};
              buildEnabled = appCfg.build.enable or false || hasLangPackage;
            in
            lib.optionalAttrs buildEnabled {
              enabled = true;
              hasPackage = hasLangPackage || appCfg.package or null != null;
            };
        };
      }
    ) appNames
  );
in
{
  options.stackpanel.appModules = lib.mkOption {
    type = lib.types.listOf lib.types.deferredModule;
    default = [ ];
    description = ''
      Additional modules to extend app configuration options.

      This allows other modules to add functionality to each app, such as
      scaffolding, IDE support, deployment settings, etc.

      These modules are applied to each app under `stackpanel.apps.<appName>.<module>`.
    '';
  };

  options.stackpanel.apps = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submoduleWith {
        modules = [
          # Proto-derived options (name, path, install-command, etc.)
          { options = db.asOptions db.extend.app; }
          # Nix-specific runtime options (tooling, offset, domain, tls)
          nixAppOptionsModule
        ]
        ++ config.stackpanel.appModules;
        specialArgs = { inherit lib; };
      }
    );
    default = { };
    description = ''
      # Stackpanel apps

      Applications in the workspace, keyed by stable app identifier. The key is
      used for deterministic port computation, generated variable names, tooling
      wrappers, and module extensions such as Go, Bun, IDE, and deployment.

      Ports are computed from the repository key and app key. The legacy `offset`
      field is retained as metadata for older base-port layouts, but the active
      stable-port computation does not use it.

      Set `domain` to register a local virtual host. The final host is
      `<domain>.<stackpanel.ports.project-name>.<stackpanel.caddy.tld>`, and the
      computed URL is exposed at `stackpanel.appsComputed.<name>.url`. Set `tls`
      to switch that computed URL to `https`; configure Caddy/Step CA separately
      for trusted local certs.
    '';
    example = lib.literalExpression ''
      {
        web = {
          name = "Web app";
          path = "apps/web";
          packageName = "@acme/web";
        };

        api = {
          name = "API server";
          path = "apps/api";
          domain = "api"; # api.<project>.localhost
          tls = true;     # https://api.<project>.localhost
        };

        docs = {
          path = "apps/docs";
          domain = "docs"; # docs.<project>.localhost
        };

        worker = {
          path = "apps/worker";
          offset = 3; # legacy metadata; stable hashed port still wins
        };
      }
    '';
  };

  # Expose computed app info for programmatic access
  options.stackpanel.appsComputed = lib.mkOption {
    type = lib.types.attrsOf (lib.types.attrsOf lib.types.unspecified);
    readOnly = true;
    description = ''
      Computed app configurations with ports and URLs.

      When pkgs is available, includes wrappedTooling derivations.
      When pkgs is not available (e.g., flake-parts top-level), wrappedTooling is null.
    '';
  };

  # Set computed values in config
  config.stackpanel.appsComputed = computedApps;

  # ===========================================================================
  # Contribute computed app ports to stackpanel.variables
  # ===========================================================================
  # Each app gets computed variables for port and URL.
  # These use the /computed/ prefix to indicate they are read-only.
  #
  # Example:
  #   config.stackpanel.variables."/computed/apps/web/port".value  # "3000"
  #   config.stackpanel.variables."/computed/apps/web/url".value   # "https://web.localhost"
  # ===========================================================================
  config.stackpanel.variables = lib.mkMerge (
    lib.mapAttrsToList (
      appName: appComputed:
      {
        # Port variable (computed, read-only)
        "/computed/apps/${appName}/port" = {
          value = toString appComputed.port;
        };
      }
      // lib.optionalAttrs (appComputed.url != null) {
        # URL variable (only if domain is configured)
        "/computed/apps/${appName}/url" = {
          value = appComputed.url;
        };
      }
    ) computedApps
  );
}
