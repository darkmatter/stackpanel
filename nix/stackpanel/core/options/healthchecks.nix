# ==============================================================================
# healthchecks.nix - Runtime probe sugar and the health panel
#
# `stackpanel.healthchecks.modules.<module>.checks.<name>` is the pre-`doctor`
# way to declare runtime probes. It still works: every check is written into
# `stackpanel.doctor.<module>.<name>` with `scope = "runtime"`, and the module
# level `enable` / `displayName` carry over unchanged.
#
# Prefer declaring probes directly:
#
#   stackpanel.doctor.go.go-installed = {
#     scope = "runtime";
#     script = "command -v go >/dev/null 2>&1";
#     severity = "critical";
#   };
#
# The computed outputs (`healthchecksComputed`, `healthchecksList`) are
# read-only views defined in doctor.nix. They keep the `Healthcheck` wire shape
# and `HEALTHCHECK_TYPE_*` / `HEALTHCHECK_SEVERITY_*` enum strings consumed by
# the agent API and the studio traffic lights:
#   🟢 Green  - All checks passing
#   🟡 Yellow - Some non-critical checks failing
#   🔴 Red    - Critical checks failing
#   ⚪ Grey   - Checks haven't run or are disabled
#
# Script-type checks support multiple content sources:
#   - script: Inline shell script content
#   - path: Path to script file (content read at eval time)
#   - scriptRef: Reference to a stackpanel.scripts.* entry
#   - scriptPackage: An existing executable derivation
# ==============================================================================
{
  lib,
  config,
  ...
}:
let
  cfg = config.stackpanel.healthchecks;

  severityType = lib.types.enum [
    "critical" # Failing = unhealthy status (red)
    "warning" # Failing = degraded status (yellow)
    "info" # Informational only (doesn't affect status)
  ];

  checkTypeType = lib.types.enum [
    "script" # Shell script that returns 0 for healthy
    "nix" # Nix expression that evaluates to true/false
    "http" # HTTP endpoint check
    "tcp" # TCP port check
  ];

  # Single healthcheck definition (deprecated spelling of a runtime doctor check)
  healthcheckType = lib.types.submodule (
    { name, ... }:
    {
      options = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether this individual healthcheck should run and be shown in status output.";
          example = false;
        };

        name = lib.mkOption {
          type = lib.types.str;
          default = name;
          description = "Display name for this healthcheck in the UI and agent API.";
          example = "PostgreSQL accepts connections";
        };

        description = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Human-readable explanation of what this check verifies.";
          example = "Verifies the local PostgreSQL service accepts TCP connections.";
        };

        type = lib.mkOption {
          type = checkTypeType;
          default = "script";
          description = ''
            Healthcheck execution mode.

            - `script`: execute a shell script from `script`, `path`, `scriptRef`, or `scriptPackage`; exit code 0 is healthy.
            - `nix`: evaluate `nixExpr`; boolean true is healthy.
            - `http`: request `httpUrl` with `httpMethod`; `httpExpectedStatus` is healthy.
            - `tcp`: open a TCP connection to `tcpHost:tcpPort`; connect success is healthy.
          '';
          example = "http";
        };

        severity = lib.mkOption {
          type = severityType;
          default = "warning";
          description = ''
            How failure affects the module aggregate status.

            - `critical`: failure marks the module unhealthy (red).
            - `warning`: failure marks the module degraded (yellow).
            - `info`: failure is reported but does not affect aggregate status.
          '';
          example = "critical";
        };

        script = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            Inline shell script body for `type = "script"` checks.
            Mutually exclusive with `path`, `scriptRef`, and `scriptPackage`.
          '';
          example = lib.literalExpression ''
            ''${pkgs.postgresql}/bin/pg_isready -h localhost -p "$STACKPANEL_POSTGRES_PORT"
          '';
        };

        path = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = ''
            Path to a shell script file for `type = "script"` checks.
            Mutually exclusive with `script`, `scriptRef`, and `scriptPackage`.
          '';
          example = lib.literalExpression "./.stack/src/checks/postgres/can-connect.sh";
        };

        scriptRef = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            Name of a `stackpanel.scripts.<name>` entry to reuse for a script check.
            Mutually exclusive with `script`, `path`, and `scriptPackage`.
          '';
          example = "db-connect";
        };

        scriptPackage = lib.mkOption {
          type = lib.types.nullOr lib.types.package;
          default = null;
          description = "Derivation that provides the executable for a script check.";
          example = lib.literalExpression ''
            pkgs.writeShellScriptBin "check-db" "exec pg_isready -h localhost -p \"$STACKPANEL_POSTGRES_PORT\""
          '';
        };

        nixExpr = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Nix expression string for `type = \"nix\"` checks; true is healthy.";
          example = "builtins.pathExists ./flake.nix";
        };

        httpUrl = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Absolute URL requested by `type = \"http\"` checks; healthy when the response status equals `httpExpectedStatus`.";
          example = "http://localhost:3000/health";
        };

        httpMethod = lib.mkOption {
          type = lib.types.str;
          default = "GET";
          description = "HTTP method used for `type = \"http\"` checks.";
          example = "HEAD";
        };

        httpExpectedStatus = lib.mkOption {
          type = lib.types.int;
          default = 200;
          description = "HTTP status code that marks a `type = \"http\"` check as healthy.";
          example = 204;
        };

        tcpHost = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Hostname or IP address connected to by `type = \"tcp\"` checks.";
          example = "localhost";
        };

        tcpPort = lib.mkOption {
          type = lib.types.nullOr lib.types.int;
          default = null;
          description = "TCP port connected to by `type = \"tcp\"` checks.";
          example = 5432;
        };

        timeout = lib.mkOption {
          type = lib.types.int;
          default = 10;
          description = "Maximum number of seconds to wait before marking this check failed.";
          example = 5;
        };

        interval = lib.mkOption {
          type = lib.types.nullOr lib.types.int;
          default = null;
          description = ''
            How often to run this check in seconds.
            If null, check runs only on demand.
          '';
        };

        tags = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Tags used to filter or group healthchecks in UI and agent output.";
          example = [
            "database"
            "critical"
          ];
        };
      };
    }
  );

  # Module healthcheck configuration
  moduleHealthcheckType = lib.types.submodule (
    { name, ... }:
    {
      options = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable all healthchecks registered under this module key.";
          example = true;
        };

        displayName = lib.mkOption {
          type = lib.types.str;
          default = name;
          description = "Display name for this module's health summary in the UI.";
          example = "PostgreSQL";
        };

        checks = lib.mkOption {
          type = lib.types.attrsOf healthcheckType;
          default = { };
          description = ''
            Named healthchecks that contribute to this module's aggregate status.

            Attribute names are stable IDs used in serialized output and should
            be lower-kebab-case. Each check may choose a different `type` and
            `severity`.
          '';
          example = lib.literalExpression ''
            {
              db-ready = {
                type = "tcp";
                tcpHost = "localhost";
                tcpPort = 5432;
                severity = "critical";
              };
              migrations-current = {
                scriptRef = "db-migrate-check";
                severity = "warning";
              };
            }
          '';
        };
      };
    }
  );

  # ---------------------------------------------------------------------------
  # Sugar: lower each legacy module entry onto doctor runtime-scope checks
  # ---------------------------------------------------------------------------
  toDoctorCheck = c: {
    scope = "runtime";
    inherit (c)
      enable
      name
      description
      type
      severity
      script
      path
      scriptRef
      scriptPackage
      nixExpr
      httpUrl
      httpMethod
      httpExpectedStatus
      tcpHost
      tcpPort
      timeout
      interval
      tags
      ;
  };

  # ---------------------------------------------------------------------------
  # Panel data (read from the unified store so directly-declared doctor checks
  # show up too)
  # ---------------------------------------------------------------------------
  runtimeChecksOf =
    mod:
    lib.filterAttrs (_: c: c.scope == "runtime") (
      builtins.removeAttrs mod [
        "enable"
        "displayName"
      ]
    );

  enabledModules = lib.filterAttrs (
    _: mod: mod.enable && runtimeChecksOf mod != { }
  ) config.stackpanel.doctor;
in
{
  options.stackpanel.healthchecks = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable the healthcheck UI panel built from runtime-scope doctor checks.";
      example = true;
    };

    modules = lib.mkOption {
      type = lib.types.attrsOf moduleHealthcheckType;
      default = { };
      description = ''
        Deprecated: declare runtime probes under `stackpanel.doctor.<module>.<name>`
        with `scope = "runtime"` instead.

        Healthchecks organized by module. Each entry is written into
        `stackpanel.doctor.<module>` unchanged, so existing declarations keep
        working and appear in the same traffic lights.
      '';
      example = lib.literalExpression ''
        {
          go = {
            displayName = "Go";
            checks = {
              go-installed = {
                script = "command -v go >/dev/null 2>&1";
                severity = "critical";
              };
            };
          };
        }
      '';
    };

    defaultTimeout = lib.mkOption {
      type = lib.types.int;
      default = 10;
      description = "Default timeout in seconds used by healthchecks that do not specify their own timeout.";
      example = 15;
    };

    defaultInterval = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = 30;
      description = ''
        Default interval for automatic healthcheck runs in seconds.
        Set to null to disable automatic checks.
      '';
      example = 60;
    };
  };

  config = lib.mkMerge [
    {
      stackpanel.doctor = lib.mapAttrs (
        _: mc:
        {
          inherit (mc) enable displayName;
        }
        // lib.mapAttrs (_: toDoctorCheck) mc.checks
      ) cfg.modules;
    }

    (lib.mkIf cfg.enable {
      # Register healthchecks module panel for the UI (not an extension - core module)
      stackpanel.panels.healthchecks-overview = {
        module = "healthchecks";
        title = "System Health";
        description = "Overview of healthcheck status across enabled Stackpanel modules";
        icon = "activity";
        type = "PANEL_TYPE_STATUS";
        order = 5;
        fields = [
          {
            name = "metrics";
            type = "FIELD_TYPE_STRING";
            value = builtins.toJSON (
              lib.mapAttrsToList (
                _moduleName: mod:
                let
                  enabledChecks = lib.filterAttrs (_: c: c.enable) (runtimeChecksOf mod);
                  enabledCount = lib.length (lib.attrNames enabledChecks);
                in
                {
                  label = mod.displayName;
                  value = "${toString enabledCount} checks";
                  status = if enabledCount > 0 then "ok" else "warning";
                }
              ) enabledModules
            );
          }
        ];
        # Include module summary as app data
        apps = lib.mapAttrs (_moduleName: mod: {
          enabled = mod.enable;
          config = {
            inherit (mod) displayName;
            checkCount = toString (lib.length (lib.attrNames (runtimeChecksOf mod)));
          };
        }) enabledModules;
      };
    })
  ];
}
