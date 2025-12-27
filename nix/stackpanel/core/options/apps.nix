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
  # Apps use offset 0-9 (services use 10+)
  appsBaseOffset = 0;

  # Get the project base port
  projectBasePort = portsCfg.base-port;

  # App option type (just user inputs, no computed fields)
  appType = lib.types.submodule {
    options = {
      offset = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = ''
          Port offset from base port.
          If null, offset is determined by position in apps attrset.
        '';
        example = 5;
      };

      domain = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Domain prefix for .localhost vhost.
          If set, a Caddy vhost will be created at <domain>.localhost
        '';
        example = "api";
      };

      tls = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable TLS for the vhost (requires Step CA)";
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
        port = projectBasePort + appsBaseOffset + offset;
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
  options.stackpanel.apps = lib.mkOption {
    type = lib.types.attrsOf appType;
    default = {};
    description = ''
      Apps to assign ports and optionally create Caddy vhosts for.
      Each app gets a port starting at basePort + 10.
    '';
    example = lib.literalExpression ''
      {
        web = {};
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
