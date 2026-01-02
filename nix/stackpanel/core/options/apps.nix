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
# ==============================================================================
{
  lib,
  config,
  ...
}: let

  # Get user-defined apps (before computed values)
  rawApps = config.stackpanel.apps;
  portsCfg = config.stackpanel.ports;
  repoKey = rawApps.github or "darkmatter/stackpanel";
  portsLib = import ../../lib/ports.nix { inherit lib; };
  # Apps use offset 0-9 (services use 10+)
  appsBaseOffset = 0;

  # Get the project base port
  projectBasePort = portsCfg.base-port;

  # Base app option type (just user inputs, no computed fields)
  baseAppModule = { lib, ... }: {
    options = {
      name = lib.mkOption {
        description = ''
          Name of the application - mainly used for display purposes.
        '';
        type = lib.types.str;
      };
      path = lib.mkOption {
        description = ''
          Path to app directory relative to repo root.
          Optional unless required by a specific app module.
        '';
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "apps/web";
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
      domain = lib.mkOption {
        description = ''
          Domain prefix for .localhost vhost.
          If set, a Caddy vhost will be created at <domain>.localhost
        '';
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "api";
      };
      tls = lib.mkOption {
        description = "Enable TLS for the vhost (requires Step CA)";
        type = lib.types.bool;
        default = false;
      };
    };
  };

  # Compute full app configurations with ports
  appNames = lib.attrNames rawApps;
  computedApps = lib.listToAttrs (lib.imap0 (
      idx: name: let
        appCfg = rawApps.${name};
        offset =
          if appCfg.offset != null
          then appCfg.offset
          else idx;
        port = portsLib.stablePort {
          repo = repoKey;
          service = name;
        };
        domain =
          if appCfg.domain != null
          then "${appCfg.domain}.localhost"
          else null;
        protocol =
          if appCfg.tls
          then "https"
          else "http";
        url =
          if domain != null
          then "${protocol}://${domain}"
          else null;
      in {
        inherit name;
        value = {
          inherit port domain url;
          inherit (appCfg) tls offset;
        };
      }
    )
    appNames);
in {
  options.stackpanel.appModules = lib.mkOption {
    type = lib.types.listOf lib.types.deferredModule;
    default = [];
    description = ''
      Additional modules to extend app configuration options.

      This allows other modules to add functionality to each app, such as
      scaffolding, IDE support, deployment settings, etc.

      These modules are applied to each app under `stackpanel.apps.<appName>.<module>`.
    '';
  };
  options.stackpanel.apps = lib.mkOption {
    # type = lib.types.attrsOf appType;
    type = lib.types.attrsOf (lib.types.submoduleWith {
      modules = [ baseAppModule ] ++ config.stackpanel.appModules;
      specialArgs = { inherit lib; };
    });
    default = {};
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
    default = computedApps;
    description = "Computed app configurations with ports and URLs";
  };
}
