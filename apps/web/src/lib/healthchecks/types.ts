/**
 * Healthchecks Type Definitions
 *
 * Types for the module healthchecks system. These mirror the Go types
 * in the agent server and the proto schema definitions.
 *
 * The healthchecks system provides "traffic light" status indicators
 * for each module in the Stackpanel UI.
 */

// =============================================================================
// Health Status (traffic light state)
// =============================================================================

export type HealthStatus =
  | "HEALTH_STATUS_UNSPECIFIED"
  | "HEALTH_STATUS_HEALTHY" // 🟢 Green - All checks passing
  | "HEALTH_STATUS_DEGRADED" // 🟡 Yellow - Some non-critical checks failing
  | "HEALTH_STATUS_UNHEALTHY" // 🔴 Red - Critical checks failing
  | "HEALTH_STATUS_UNKNOWN" // ⚪ Grey - Checks haven't run yet
  | "HEALTH_STATUS_DISABLED"; // Healthchecks disabled for this module

// =============================================================================
// Healthcheck Type (how the check is evaluated)
// =============================================================================

export type HealthcheckType =
  | "HEALTHCHECK_TYPE_UNSPECIFIED"
  | "HEALTHCHECK_TYPE_SCRIPT" // Shell script that returns 0 for healthy
  | "HEALTHCHECK_TYPE_NIX" // Nix expression that evaluates to true/false
  | "HEALTHCHECK_TYPE_HTTP" // HTTP endpoint check
  | "HEALTHCHECK_TYPE_TCP"; // TCP port check

// =============================================================================
// Healthcheck Severity (how critical the check is)
// =============================================================================

export type HealthcheckSeverity =
  | "HEALTHCHECK_SEVERITY_UNSPECIFIED"
  | "HEALTHCHECK_SEVERITY_CRITICAL" // Failing = unhealthy (red)
  | "HEALTHCHECK_SEVERITY_WARNING" // Failing = degraded (yellow)
  | "HEALTHCHECK_SEVERITY_INFO"; // Informational only

// =============================================================================
// Healthcheck Definition
// =============================================================================

export interface Healthcheck {
  /** Unique identifier for the healthcheck */
  id: string;
  /** Display name for the healthcheck */
  name: string;
  /** Description of what this check verifies */
  description?: string;
  /** Type of healthcheck (script, nix, http, tcp) */
  type: HealthcheckType;
  /** How critical this check is */
  severity: HealthcheckSeverity;

  // Script-based checks
  /** Shell script content (for SCRIPT type) */
  script?: string;
  /** Path to script derivation (resolved from Nix) */
  scriptPath?: string;

  // Nix-based checks
  /** Nix expression to evaluate (for NIX type) */
  nixExpr?: string;

  // HTTP-based checks
  /** URL to check (for HTTP type) */
  httpUrl?: string;
  /** HTTP method (GET, POST, etc.) */
  httpMethod?: string;
  /** Expected HTTP status code */
  httpExpectedStatus?: number;

  // TCP-based checks
  /** Host to connect to (for TCP type) */
  tcpHost?: string;
  /** Port to connect to (for TCP type) */
  tcpPort?: number;

  // Timing
  /** Timeout for the check in seconds */
  timeout: number;
  /** How often to run this check (optional) */
  interval?: number;

  // Metadata
  /** Module that registered this healthcheck */
  module: string;
  /** Tags for filtering/grouping checks */
  tags?: string[];
  /** Whether this check is enabled */
  enabled: boolean;
}

// =============================================================================
// Healthcheck Result
// =============================================================================

export interface HealthcheckResult {
  /** ID of the healthcheck that was run */
  checkId: string;
  /** Result status of this check */
  status: HealthStatus;
  /** Human-readable result message */
  message?: string;
  /** Error message if check failed to execute */
  error?: string;
  /** Raw output from script/command */
  output?: string;
  /** How long the check took to run in milliseconds */
  durationMs: number;
  /** When the check was run (RFC3339) */
  timestamp: string;
  /** Original healthcheck definition (for UI display) */
  check?: Healthcheck;
}

// =============================================================================
// Module Health (aggregated status for a module)
// =============================================================================

export interface ModuleHealth {
  /** Module name */
  module: string;
  /** Display name for the module */
  displayName: string;
  /** Aggregated health status */
  status: HealthStatus;
  /** Individual check results */
  checks: HealthcheckResult[];
  /** Number of passing checks */
  healthyCount: number;
  /** Total number of checks */
  totalCount: number;
  /** When health was last evaluated (RFC3339) */
  lastUpdated: string;
}

// =============================================================================
// Health Summary (overall system health)
// =============================================================================

export interface HealthSummary {
  /** Overall system health status */
  overallStatus: HealthStatus;
  /** Health status per module */
  modules: Record<string, ModuleHealth>;
  /** Total healthy checks across all modules */
  totalHealthy: number;
  /** Total checks across all modules */
  totalChecks: number;
  /** When summary was last computed (RFC3339) */
  lastUpdated: string;
}

// =============================================================================
// API Response Types
// =============================================================================

export interface HealthchecksResponse {
  /** Health summary data */
  data: HealthSummary;
  /** Whether data was from cache */
  cached?: boolean;
  /** Error message if request failed */
  error?: string;
}

// =============================================================================
// SSE Event Types
// =============================================================================

export interface HealthchecksUpdatedEvent {
  type: "healthchecks.updated";
  data: HealthSummary;
}

/** Fired when a POST /api/healthchecks begins running checks */
export interface HealthchecksRunningEvent {
  type: "healthchecks.running";
  data: {
    /** IDs of checks that are about to be evaluated */
    checkIds: string[];
    /** Module filter (empty string if running all) */
    module: string;
  };
}

/** Fired for each individual check result as it completes */
export interface HealthcheckResultEvent {
  type: "healthcheck.result";
  data: HealthcheckResult;
}

// =============================================================================
// Component Props
// =============================================================================

/** Props for the traffic light indicator component */
export interface TrafficLightProps {
  /** Current health status */
  status: HealthStatus;
  /** Size of the indicator */
  size?: "sm" | "md" | "lg";
  /** Whether to show a pulse animation for healthy status */
  pulse?: boolean;
  /** Optional label to show next to the indicator */
  label?: string;
  /** Whether the indicator is clickable */
  onClick?: () => void;
}

/** Props for the module health card component */
export interface ModuleHealthCardProps {
  /** Module health data */
  moduleHealth: ModuleHealth;
  /** Whether to show individual check details */
  showDetails?: boolean;
  /** Callback when user clicks to run checks */
  onRunChecks?: () => void;
}

/** Props for the health summary panel component */
export interface HealthSummaryPanelProps {
  /** Health summary data */
  summary: HealthSummary | null;
  /** Whether data is loading */
  isLoading?: boolean;
  /** Error message if load failed */
  error?: string;
  /** Callback to refresh health data */
  onRefresh?: () => void;
}

// =============================================================================
// Utility Types
// =============================================================================

/** Map of status to display properties */
export interface StatusDisplayProps {
  /** CSS color class */
  colorClass: string;
  /** Background color class */
  bgClass: string;
  /** Icon to display */
  icon: "check" | "warning" | "error" | "unknown" | "disabled";
  /** Human-readable label */
  label: string;
}

/** Get display properties for a health status */
export const STATUS_DISPLAY: Record<HealthStatus, StatusDisplayProps> = {
  HEALTH_STATUS_UNSPECIFIED: {
    colorClass: "text-muted-foreground",
    bgClass: "bg-muted",
    icon: "unknown",
    label: "Unknown",
  },
  HEALTH_STATUS_HEALTHY: {
    colorClass: "text-green-500",
    bgClass: "bg-green-500",
    icon: "check",
    label: "Healthy",
  },
  HEALTH_STATUS_DEGRADED: {
    colorClass: "text-yellow-500",
    bgClass: "bg-yellow-500",
    icon: "warning",
    label: "Degraded",
  },
  HEALTH_STATUS_UNHEALTHY: {
    colorClass: "text-red-500",
    bgClass: "bg-red-500",
    icon: "error",
    label: "Unhealthy",
  },
  HEALTH_STATUS_UNKNOWN: {
    colorClass: "text-muted-foreground",
    bgClass: "bg-muted",
    icon: "unknown",
    label: "Unknown",
  },
  HEALTH_STATUS_DISABLED: {
    colorClass: "text-muted-foreground",
    bgClass: "bg-muted",
    icon: "disabled",
    label: "Disabled",
  },
};
