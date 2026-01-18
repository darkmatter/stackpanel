# ==============================================================================
# healthchecks.proto.nix
#
# Protobuf schema for module healthchecks.
# Defines healthcheck types, status enums, and result structures.
#
# Modules can declare healthchecks that verify their functionality is working.
# Each healthcheck can be either a Nix expression or a shell script.
# ==============================================================================
{ lib }:
let
  proto = import ../lib/proto.nix { inherit lib; };
in
proto.mkProtoFile {
  name = "healthchecks.proto";
  package = "stackpanel.db";

  options = {
    go_package = "github.com/darkmatter/stackpanel/packages/proto/gen/go";
  };

  enums = {
    # Type of healthcheck (how it's evaluated)
    HealthcheckType = proto.mkEnum {
      name = "HealthcheckType";
      description = "The type of healthcheck evaluation";
      values = [
        "HEALTHCHECK_TYPE_UNSPECIFIED"
        "HEALTHCHECK_TYPE_SCRIPT" # Shell script that returns 0 for healthy
        "HEALTHCHECK_TYPE_NIX" # Nix expression that evaluates to true/false
        "HEALTHCHECK_TYPE_HTTP" # HTTP endpoint check
        "HEALTHCHECK_TYPE_TCP" # TCP port check
      ];
    };

    # Current health status
    HealthStatus = proto.mkEnum {
      name = "HealthStatus";
      description = "The current health status of a module or check";
      values = [
        "HEALTH_STATUS_UNSPECIFIED"
        "HEALTH_STATUS_HEALTHY" # All checks passing (green)
        "HEALTH_STATUS_DEGRADED" # Some checks failing (yellow)
        "HEALTH_STATUS_UNHEALTHY" # Critical checks failing (red)
        "HEALTH_STATUS_UNKNOWN" # Checks haven't run yet (grey)
        "HEALTH_STATUS_DISABLED" # Healthchecks disabled for this module
      ];
    };

    # Severity of a healthcheck
    HealthcheckSeverity = proto.mkEnum {
      name = "HealthcheckSeverity";
      description = "How critical a healthcheck is";
      values = [
        "HEALTHCHECK_SEVERITY_UNSPECIFIED"
        "HEALTHCHECK_SEVERITY_CRITICAL" # Failing = unhealthy status
        "HEALTHCHECK_SEVERITY_WARNING" # Failing = degraded status
        "HEALTHCHECK_SEVERITY_INFO" # Informational only, doesn't affect status
      ];
    };
  };

  messages = {
    # Definition of a single healthcheck
    Healthcheck = proto.mkMessage {
      name = "Healthcheck";
      description = "A healthcheck definition that can verify module functionality";
      fields = {
        id = proto.string 1 "Unique identifier for the healthcheck";
        name = proto.string 2 "Display name for the healthcheck";
        description = proto.optional (proto.string 3 "Description of what this check verifies");
        type = proto.message "HealthcheckType" 4 "Type of healthcheck (script, nix, http, tcp)";
        severity = proto.message "HealthcheckSeverity" 5 "How critical this check is";

        # Script-based checks
        script = proto.optional (proto.string 6 "Shell script content (for SCRIPT type)");
        script_path = proto.optional (proto.string 7 "Path to script derivation (resolved from Nix)");

        # Nix-based checks
        nix_expr = proto.optional (proto.string 8 "Nix expression to evaluate (for NIX type)");

        # HTTP-based checks
        http_url = proto.optional (proto.string 9 "URL to check (for HTTP type)");
        http_method = proto.optional (proto.string 10 "HTTP method (GET, POST, etc.)");
        http_expected_status = proto.optional (proto.int32 11 "Expected HTTP status code");

        # TCP-based checks
        tcp_host = proto.optional (proto.string 12 "Host to connect to (for TCP type)");
        tcp_port = proto.optional (proto.int32 13 "Port to connect to (for TCP type)");

        # Timing
        timeout_seconds = proto.int32 14 "Timeout for the check in seconds";
        interval_seconds = proto.optional (proto.int32 15 "How often to run this check (optional)");

        # Metadata
        module = proto.string 16 "Module that registered this healthcheck";
        tags = proto.repeated (proto.string 17 "Tags for filtering/grouping checks");
      };
    };

    # Result of running a healthcheck
    HealthcheckResult = proto.mkMessage {
      name = "HealthcheckResult";
      description = "The result of executing a healthcheck";
      fields = {
        check_id = proto.string 1 "ID of the healthcheck that was run";
        status = proto.message "HealthStatus" 2 "Result status of this check";
        message = proto.optional (proto.string 3 "Human-readable result message");
        error = proto.optional (proto.string 4 "Error message if check failed to execute");
        output = proto.optional (proto.string 5 "Raw output from script/command");
        duration_ms = proto.int64 6 "How long the check took to run in milliseconds";
        timestamp = proto.string 7 "When the check was run (RFC3339)";
      };
    };

    # Health status for a module
    ModuleHealth = proto.mkMessage {
      name = "ModuleHealth";
      description = "Aggregated health status for a module";
      fields = {
        module = proto.string 1 "Module name";
        status = proto.message "HealthStatus" 2 "Aggregated health status";
        checks = proto.repeated (proto.message "HealthcheckResult" 3 "Individual check results");
        healthy_count = proto.int32 4 "Number of passing checks";
        total_count = proto.int32 5 "Total number of checks";
        last_updated = proto.string 6 "When health was last evaluated (RFC3339)";
      };
    };

    # Collection of all module health statuses
    HealthSummary = proto.mkMessage {
      name = "HealthSummary";
      description = "Overall health summary across all modules";
      fields = {
        overall_status = proto.message "HealthStatus" 1 "Overall system health status";
        modules = proto.map "string" "ModuleHealth" 2 "Health status per module";
        total_healthy = proto.int32 3 "Total healthy checks across all modules";
        total_checks = proto.int32 4 "Total checks across all modules";
        last_updated = proto.string 5 "When summary was last computed (RFC3339)";
      };
    };
  };
}
