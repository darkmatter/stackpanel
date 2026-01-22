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
# Script-type checks support multiple content sources:
#   - script: Inline shell script content
#   - path: Path to script file (content read at eval time)
#   - scriptRef: Reference to a stackpanel.scripts.* entry
#
# The UI displays a "traffic light" indicator for each module:
#   🟢 Green  - All checks passing
#   🟡 Yellow - Some non-critical checks failing
#   🔴 Red    - Critical checks failing
#   ⚪ Grey   - Checks haven't run or are disabled
#
# Usage (inline script):
#   stackpanel.healthchecks.modules.go.checks.go-installed = {
#     script = "command -v go >/dev/null 2>&1";
#     severity = "critical";
#   };
#
# Usage (path to file):
#   stackpanel.healthchecks.modules.postgres.checks.can-connect = {
#     path = ./.stackpanel/src/checks/postgres/can-connect.sh;
#     severity = "critical";
#   };
#
# Usage (reference to script):
#   stackpanel.healthchecks.modules.db.checks.can-seed = {
#     scriptRef = "db-seed";  # Uses stackpanel.scripts.db-seed
#     severity = "warning";
#   };
#
# Extension modules use the extension name as the module key:
#   stackpanel.healthchecks.modules.sst.checks.configured = { ... };
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

        # Script-based checks - multiple ways to provide script content
        script = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            Shell script content for script-type checks (inline).
            Should exit 0 for healthy, non-zero for unhealthy.
            Mutually exclusive with `path` and `scriptRef`.
          '';
          example = "command -v go >/dev/null 2>&1";
        };

        path = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = ''
            Path to script file for script-type checks.
            Content is read and used as the script body.
            Mutually exclusive with `script` and `scriptRef`.
          '';
          example = lib.literalExpression "./.stackpanel/src/checks/postgres/can-connect.sh";
        };

        scriptRef = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            Reference to a stackpanel.scripts.* entry.
            The referenced script is used as the healthcheck command.
            Mutually exclusive with `script` and `path`.
          '';
          example = "db-connect";
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
  # All script-type checks become derivations for security (no sh -c with inline content)
  mkHealthcheckScript =
    moduleName: checkName: check:
    let
      hasScript = check.script or null != null;
      hasScriptRef = check.scriptRef or null != null;
      hasPath = check.path or null != null;
      hasScriptPackage = check.scriptPackage or null != null;

      checkName' = "${moduleName}-${checkName}";
    in
    if !hasPkgs then
      null
    else if hasScriptPackage then
      # Explicit script package provided
      check.scriptPackage
    else if hasScriptRef then
      # Reference to a stackpanel.scripts.* entry - use its derivation
      let
        refName = check.scriptRef;
        scriptPkgs = config.stackpanel.scriptsConfig.packages or { };
        refPkg = scriptPkgs.${refName} or null;
      in
      if refPkg == null then
        throw "Healthcheck '${checkName'}': scriptRef '${refName}' not found in stackpanel.scripts"
      else
        refPkg
    else if hasPath then
      # Build derivation from path content
      pkgs.writeShellApplication {
        name = "healthcheck-${checkName'}";
        text = builtins.readFile check.path;
      }
    else if hasScript then
      # Build derivation from inline script
      pkgs.writeShellApplication {
        name = "healthcheck-${checkName'}";
        text = check.script;
      }
    else
      # Non-script type check (http, tcp, nix) - no derivation needed
      null;

  # Compute serializable healthcheck data for the agent
  computeSerializableChecks =
    moduleName: moduleConfig:
    lib.mapAttrs (
      checkName: check:
      let
        # Build the script derivation
        scriptDrv = mkHealthcheckScript moduleName checkName check;

        # Resolve script content based on source type
        hasScript = check.script or null != null;
        hasScriptRef = check.scriptRef or null != null;
        hasPath = check.path or null != null;

        # Validate mutually exclusive options
        sourceCount = lib.count (x: x) [ hasScript hasPath hasScriptRef ];
      in
      assert sourceCount <= 1 || throw "Healthcheck '${moduleName}.${checkName}': specify only one of 'script', 'path', or 'scriptRef'";
      let

        # Determine the source type for debugging
        scriptSource =
          if check.scriptPackage or null != null then "package"
          else if hasScriptRef then "scriptRef:${check.scriptRef}"
          else if hasPath then "path"
          else if hasScript then "inline"
          else null;

        # Get the binary path for script-type checks
        checkName' = "${moduleName}-${checkName}";
        scriptBinPath =
          if scriptDrv != null then
            if hasScriptRef then
              "${scriptDrv}/bin/${check.scriptRef}"
            else
              "${scriptDrv}/bin/healthcheck-${checkName'}"
          else
            null;
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
        # For script-type checks: agent executes scriptPath directly (no sh -c)
        scriptPath = scriptBinPath;
        # Provide derivation path so agent can build if not realized
        scriptDrvPath = if scriptDrv != null then builtins.toString scriptDrv.drvPath else null;
        scriptSource = scriptSource;
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
            displayName = "Go";
            checks = {
              # Inline script
              go-installed = {
                script = "command -v go >/dev/null 2>&1";
                severity = "critical";
              };
            };
          };

          postgres = {
            displayName = "PostgreSQL";
            checks = {
              # TCP check
              running = {
                type = "tcp";
                tcpHost = "localhost";
                tcpPort = 5432;
                severity = "critical";
              };
              # Path to script file
              has-tables = {
                path = ./.stackpanel/src/checks/postgres/has-tables.sh;
                severity = "warning";
              };
            };
          };

          # Extension module
          sst = {
            displayName = "SST";
            checks = {
              configured = {
                path = ./src/checks/configured.sh;
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
    # Register healthchecks module panel for the UI (not an extension - core module)
    stackpanel.panels.healthchecks-overview = {
      module = "healthchecks";
      title = "System Health";
      description = "Overview of module health status";
      icon = "activity";
      type = "PANEL_TYPE_STATUS";
      order = 5;
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
