# ==============================================================================
# healthchecks.nix
#
# Healthcheck configuration options for Stackpanel modules.
#
# Modules can declare healthchecks that verify their functionality is working.
# Each healthcheck can be:
#   - A shell script (returns 0 for healthy)
#   - A Nix expression (evaluates to true/false)
#   - An HTTP endpoint check
#   - A TCP port check
#
# The UI displays a "traffic light" indicator for each module:
#   🟢 Green  - All checks passing
#   🟡 Yellow - Some non-critical checks failing
#   🔴 Red    - Critical checks failing
#   ⚪ Grey   - Checks haven't run or are disabled
#
# Usage:
#   stackpanel.healthchecks.modules.go = {
#     enable = true;
#     checks = {
#       go-installed = {
#         name = "Go Installed";
#         type = "script";
#         script = "command -v go >/dev/null 2>&1";
#         severity = "critical";
#       };
#       go-version = {
#         name = "Go Version";
#         type = "script";
#         script = ''
#           version=$(go version 2>/dev/null | grep -oP '\d+\.\d+')
#           [ "$(printf '%s\n' "1.21" "$version" | sort -V | head -n1)" = "1.21" ]
#         '';
#         severity = "warning";
#       };
#     };
#   };
#
# The healthchecks are exposed via the agent API for the web UI to consume
# and display traffic light indicators.
# ==============================================================================
{
  lib,
  config,
  pkgs ? null,
  ...
}:
let
  cfg = config.stackpanel.healthchecks;

  # Check if pkgs is available (needed for script derivations)
  hasPkgs = pkgs != null;

  # Healthcheck severity type
  severityType = lib.types.enum [
    "critical" # Failing = unhealthy status (red)
    "warning" # Failing = degraded status (yellow)
    "info" # Informational only (doesn't affect status)
  ];

  # Healthcheck type enum
  checkTypeType = lib.types.enum [
    "script" # Shell script that returns 0 for healthy
    "nix" # Nix expression that evaluates to true/false
    "http" # HTTP endpoint check
    "tcp" # TCP port check
  ];

  # Single healthcheck definition
  healthcheckType = lib.types.submodule (
    { name, ... }:
    {
      options = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether this healthcheck is enabled";
        };

        name = lib.mkOption {
          type = lib.types.str;
          default = name;
          description = "Display name for the healthcheck";
        };

        description = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Description of what this check verifies";
        };

        type = lib.mkOption {
          type = checkTypeType;
          default = "script";
          description = "Type of healthcheck (script, nix, http, tcp)";
        };

        severity = lib.mkOption {
          type = severityType;
          default = "warning";
          description = ''
            How critical this check is:
            - critical: Failing = unhealthy (red light)
            - warning: Failing = degraded (yellow light)
            - info: Informational only, doesn't affect status
          '';
        };

        # Script-based checks
        script = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            Shell script content for script-type checks.
            Should exit 0 for healthy, non-zero for unhealthy.
          '';
          example = "command -v go >/dev/null 2>&1";
        };

        scriptPackage = lib.mkOption {
          type = lib.types.nullOr lib.types.package;
          default = null;
          description = ''
            A derivation that provides the healthcheck script.
            The script should be at $out/bin/<name> or $out.
          '';
        };

        # Nix-based checks
        nixExpr = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            Nix expression to evaluate for nix-type checks.
            Should evaluate to true for healthy, false for unhealthy.
          '';
          example = "builtins.pathExists /nix/store";
        };

        # HTTP-based checks
        httpUrl = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "URL to check for http-type checks";
          example = "http://localhost:3000/health";
        };

        httpMethod = lib.mkOption {
          type = lib.types.str;
          default = "GET";
          description = "HTTP method to use for http-type checks";
        };

        httpExpectedStatus = lib.mkOption {
          type = lib.types.int;
          default = 200;
          description = "Expected HTTP status code for a healthy response";
        };

        # TCP-based checks
        tcpHost = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Host to connect to for tcp-type checks";
          example = "localhost";
        };

        tcpPort = lib.mkOption {
          type = lib.types.nullOr lib.types.int;
          default = null;
          description = "Port to connect to for tcp-type checks";
          example = 5432;
        };

        # Timing
        timeout = lib.mkOption {
          type = lib.types.int;
          default = 10;
          description = "Timeout for the check in seconds";
        };

        interval = lib.mkOption {
          type = lib.types.nullOr lib.types.int;
          default = null;
          description = ''
            How often to run this check in seconds.
            If null, check runs only on demand.
          '';
        };

        # Metadata
        tags = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Tags for filtering/grouping checks";
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
          description = "Enable healthchecks for this module";
        };

        displayName = lib.mkOption {
          type = lib.types.str;
          default = name;
          description = "Display name for the module in the UI";
        };

        checks = lib.mkOption {
          type = lib.types.attrsOf healthcheckType;
          default = { };
          description = "Healthchecks for this module";
        };
      };
    }
  );

  # Build script derivation for a healthcheck
  # Only use scriptPath for explicit scriptPackage - inline scripts are run directly by the agent
  mkHealthcheckScript =
    moduleName: checkName: check:
    if !hasPkgs then
      null
    else if check.scriptPackage != null then
      check.scriptPackage
    else
      # Don't create derivations for inline scripts - the Go agent runs them via `sh -c`
      null;

  # Compute serializable healthcheck data for the agent
  computeSerializableChecks =
    moduleName: moduleConfig:
    lib.mapAttrs (
      checkName: check:
      let
        scriptPath = mkHealthcheckScript moduleName checkName check;
      in
      {
        id = "${moduleName}-${checkName}";
        name = check.name;
        description = check.description;
        type =
          {
            script = "HEALTHCHECK_TYPE_SCRIPT";
            nix = "HEALTHCHECK_TYPE_NIX";
            http = "HEALTHCHECK_TYPE_HTTP";
            tcp = "HEALTHCHECK_TYPE_TCP";
          }
          .${check.type};
        severity =
          {
            critical = "HEALTHCHECK_SEVERITY_CRITICAL";
            warning = "HEALTHCHECK_SEVERITY_WARNING";
            info = "HEALTHCHECK_SEVERITY_INFO";
          }
          .${check.severity};
        script = check.script;
        scriptPath = if scriptPath != null then toString scriptPath else null;
        nixExpr = check.nixExpr;
        httpUrl = check.httpUrl;
        httpMethod = check.httpMethod;
        httpExpectedStatus = check.httpExpectedStatus;
        tcpHost = check.tcpHost;
        tcpPort = check.tcpPort;
        timeout = check.timeout;
        interval = check.interval;
        module = moduleName;
        tags = check.tags;
        enabled = check.enable;
      }
    ) (lib.filterAttrs (_: c: c.enable) moduleConfig.checks);

  # Compute all enabled healthchecks across all modules
  enabledModules = lib.filterAttrs (_: m: m.enable) cfg.modules;

  computedHealthchecks = lib.mapAttrs computeSerializableChecks enabledModules;

  # Flatten all checks into a single list for the API
  allChecks = lib.flatten (
    lib.mapAttrsToList (
      moduleName: checks: lib.mapAttrsToList (_: check: check) checks
    ) computedHealthchecks
  );
in
{
  options.stackpanel.healthchecks = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable the healthchecks system";
    };

    modules = lib.mkOption {
      type = lib.types.attrsOf moduleHealthcheckType;
      default = { };
      description = ''
        Healthchecks organized by module.

        Each module can declare multiple healthchecks that verify its
        functionality. The UI displays a traffic light for each module
        based on the aggregate status of its healthchecks.
      '';
      example = lib.literalExpression ''
        {
          go = {
            enable = true;
            displayName = "Go";
            checks = {
              go-installed = {
                name = "Go Installed";
                type = "script";
                script = "command -v go >/dev/null 2>&1";
                severity = "critical";
              };
            };
          };
          postgres = {
            enable = true;
            displayName = "PostgreSQL";
            checks = {
              postgres-running = {
                name = "PostgreSQL Running";
                type = "tcp";
                tcpHost = "localhost";
                tcpPort = 5432;
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
      description = "Default timeout for healthchecks in seconds";
    };

    defaultInterval = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = 30;
      description = ''
        Default interval for automatic healthcheck runs in seconds.
        Set to null to disable automatic checks.
      '';
    };
  };

  # Expose computed healthchecks for serialization/API
  options.stackpanel.healthchecksComputed = lib.mkOption {
    type = lib.types.attrsOf (lib.types.attrsOf lib.types.unspecified);
    readOnly = true;
    default = computedHealthchecks;
    description = "Computed healthcheck configurations (for agent API)";
  };

  # Flat list of all healthchecks
  options.stackpanel.healthchecksList = lib.mkOption {
    type = lib.types.listOf lib.types.unspecified;
    readOnly = true;
    default = allChecks;
    description = "Flat list of all healthchecks (for agent API)";
  };

  config = lib.mkIf cfg.enable {
    # Register healthchecks extension for the UI
    stackpanel.extensions.healthchecks = {
      name = "Healthchecks";
      enabled = true;
      priority = 5; # Show near the top
      tags = [
        "system"
        "monitoring"
      ];

      panels = [
        {
          id = "healthchecks-overview";
          title = "System Health";
          description = "Overview of module health status";
          type = "PANEL_TYPE_STATUS";
          order = 0;
          fields = [
            {
              name = "metrics";
              type = "FIELD_TYPE_STRING";
              value = builtins.toJSON (
                lib.mapAttrsToList (
                  moduleName: moduleConfig:
                  let
                    enabledChecks = lib.filterAttrs (_: c: c.enable) moduleConfig.checks;
                    enabledCount = lib.length (lib.attrNames enabledChecks);
                  in
                  {
                    label = moduleConfig.displayName;
                    value = "${toString enabledCount} checks";
                    status = if enabledCount > 0 then "ok" else "warning";
                  }
                ) enabledModules
              );
            }
          ];
        }
      ];

      # Include module summary as app data
      apps = lib.mapAttrs (moduleName: moduleConfig: {
        enabled = moduleConfig.enable;
        config = {
          displayName = moduleConfig.displayName;
          checkCount = toString (lib.length (lib.attrNames moduleConfig.checks));
        };
      }) enabledModules;
    };
  };
}
