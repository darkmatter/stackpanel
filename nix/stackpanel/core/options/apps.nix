# ==============================================================================
# apps.nix
#
# Application configuration options - ports and Caddy virtual hosts.
#
# Manages application ports and Caddy virtual hosts in a unified way.
# Each app gets a deterministic port and optionally a .localhost domain.
#
# Port Layout (from basePort):
#   +0 to +9:   User apps (web, server, docs, etc.)
#   +10 to +99: Infrastructure services (postgres, redis, minio, etc.)
#
# Options per app:
#   - offset: Port offset from base port (null = auto-assign by position)
#   - domain: Domain prefix for .localhost vhost (null = no vhost)
#   - tls: Enable TLS for the vhost (requires Step CA)
#
# Usage:
#   stackpanel.apps = {
#     web = {};                          # Just port (basePort + 0)
#     server = { offset = 1; };          # Port with explicit offset
#     docs = { domain = "docs"; };       # Port + docs.localhost vhost
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
  repoKey = rawApps.github or "darkmatter/stackpanel";
  portsLib = import ../../lib/ports.nix { inherit lib; };
  ports = portsLib.mkPorts { inherit lib; };
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
          description = "Optional binary name if the package provides multiple executables.";
        };
        args = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Arguments passed to the tool.";
        };
        env = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { };
          description = "Environment variables for the tool.";
        };
        configPath = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Repo-relative config file path for the tool.";
        };
        configArg = lib.mkOption {
          type = lib.types.nullOr (lib.types.listOf lib.types.str);
          default = null;
          description = "Argument prefix inserted before configPath (e.g. [\"--config\"]).";
        };
        cwd = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Override working directory (repo-relative). Defaults to app path.";
        };
      };
    };

  # Nix-specific app options (not in proto schema)
  # These are runtime/devenv options that don't belong in serialized data
  # Note: port and domain are defined in the proto schema (db.extend.app)
  nixAppOptionsModule =
    { lib, ... }:
    {
      options = {
        tooling = {
          install = lib.mkOption {
            type = lib.types.nullOr (lib.types.submodule toolStepModule);
            default = null;
            description = "Install tool definition (wrapped).";
          };
          build = lib.mkOption {
            type = lib.types.nullOr (lib.types.submodule toolStepModule);
            default = null;
            description = "Build tool definition (wrapped).";
          };
          test = lib.mkOption {
            type = lib.types.nullOr (lib.types.submodule toolStepModule);
            default = null;
            description = "Test tool definition (wrapped).";
          };
          dev = lib.mkOption {
            type = lib.types.nullOr (lib.types.submodule toolStepModule);
            default = null;
            description = "Dev tool definition (wrapped).";
          };
          build-steps = lib.mkOption {
            type = lib.types.listOf (lib.types.submodule toolStepModule);
            default = [ ];
            description = "Additional build steps (wrapped).";
          };
          formatters = lib.mkOption {
            type = lib.types.listOf (lib.types.submodule toolStepModule);
            default = [ ];
            description = "Formatter definitions (wrapped).";
          };
          linters = lib.mkOption {
            type = lib.types.listOf (lib.types.submodule toolStepModule);
            default = [ ];
            description = "Linter definitions (wrapped).";
          };
        };
        offset = lib.mkOption {
          description = ''
            Port offset from base port.
            If null, offset is determined by position in apps attrset.
          '';
          type = lib.types.nullOr lib.types.int;
          default = null;
          example = 5;
        };
        tls = lib.mkOption {
          description = "Enable TLS for the vhost (requires Step CA)";
          type = lib.types.bool;
          default = false;
        };
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
        tooling = appCfg.tooling;
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
        domain = if appCfg.domain != null then "${appCfg.domain}.localhost" else null;
        protocol = if appCfg.tls then "https" else "http";
        url = if domain != null then "${protocol}://${domain}" else null;
        tooling = appCfg.tooling;
        # Only compute wrappedTooling when pkgs is available
        wrappedTooling = if mkWrappedTooling != null then mkWrappedTooling name appCfg else null;
      in
      {
        inherit name;
        value = {
          inherit
            port
            domain
            url
            tooling
            wrappedTooling
            ;
          inherit (appCfg) tls offset;
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
          # Note: Strip the __db_extend_marker__ when using db.extend.* directly as options
          { options = removeAttrs db.extend.app [ "__db_extend_marker__" ]; }
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

      Configuration options for defining and managing applications within
      the Stackpanel environment. This module allows you to declare app-specific
      settings, dependencies, and runtime configurations that integrate with the
      Stackpanel orchestration system.

      Core configuration options are defined here. These options are extended
      by other modules to add functionality such as scaffolding, IDE support,
      and deployment settings. These are typically configured at
      `stackpanel.apps.<appName>.<module>`.

      A core stackpanel feature and convention is that each app is assigned a stable,
      deterministic port based on the repo (`organization/repo`) and app/service
      name. This allows the port to be known ahead of time without having to
      pass it around manually.

      This key will also be used as the default value by other modules lke Caddy
      to create virtual hosts for the app.

      If you encounter a collision in the port calculation, you can set
      `<appName>` to a different name to get a different port range.
    '';
    example = lib.literalExpression ''
      {
        web = {
          name = "web";
          path = "apps/web";
          tls = true;
          # Go app example - enable go features
          go = {
            enable = true;
            # Watch directories for live reload
            watchDirs = [ "cmd" "pkg" "internal" ];
            # tools.go will be automatically created, add dev tools here
            tools = [
              "github.com/golangci/golangci-lint/cmd/golangci-lint"
            ];
            # By default, turborepo integration (package.json), air live reload (.air.toml),
            # tools.go is all scaffolded automatically, but can be suppressed here
            generateFiles = true;
          };
        };
        server = { offset = 1; };
        docs = { domain = "docs"; };
        api = { domain = "api"; tls = true; };
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
  # Each app gets a PORT variable that other apps/services can reference.
  # This allows apps to discover each other's ports at runtime.
  #
  # Example:
  #   config.stackpanel.variables."/apps/web/port".value  # "3000"
  #   config.stackpanel.variables."/apps/web/port".ref    # "3000" (same for VARIABLE type)
  #   config.stackpanel.variables."/apps/web/url".value   # "https://web.localhost"
  # ===========================================================================
  config.stackpanel.variables = lib.mkMerge (
    lib.mapAttrsToList (
      appName: appComputed:
      let
        # Convert app name to uppercase for env var key
        # e.g., "web" -> "WEB", "my-app" -> "MY_APP"
        upperName = lib.toUpper (builtins.replaceStrings [ "-" ] [ "_" ] appName);
      in
      {
        # Port variable - NUMBER type for proper Zod codegen
        "/apps/${appName}/port" = {
          key = "${upperName}_PORT";
          type = "NUMBER";  # Port numbers should be typed as numbers
          value = toString appComputed.port;
          description = "Port for the ${appName} app";
          providedBy = "stackpanel.apps";
        };
      }
      // lib.optionalAttrs (appComputed.url != null) {
        # URL variable - STRING type (only if domain is configured)
        "/apps/${appName}/url" = {
          key = "${upperName}_URL";
          type = "STRING";  # URLs are strings
          value = appComputed.url;
          description = "URL for the ${appName} app";
          providedBy = "stackpanel.apps";
        };
      }
    ) computedApps
  );
}
