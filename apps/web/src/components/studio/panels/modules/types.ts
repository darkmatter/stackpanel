/**
 * Module Browser Type Definitions
 *
 * Types for the module browser system. These match the Go agent's
 * module API response format.
 */

// =============================================================================
// Module Types
// =============================================================================

export interface ModuleMeta {
  name: string;
  description?: string | null;
  icon?: string | null;
  category: string;
  author?: string | null;
  version?: string | null;
  homepage?: string | null;
}

export interface ModuleSource {
  type: "builtin" | "local" | "flake-input" | "registry";
  flakeInput?: string | null;
  path?: string | null;
  registryId?: string | null;
  ref?: string | null;
}

export interface ModuleFeatures {
  files: boolean;
  scripts: boolean;
  tasks: boolean;
  healthchecks: boolean;
  services: boolean;
  secrets: boolean;
  packages: boolean;
  appModule: boolean;
}

export interface PanelField {
  name: string;
  type: string;
  value: string;
  options?: string[];
}

export interface ModulePanel {
  id: string;
  title: string;
  description?: string | null;
  type: string;
  order: number;
  fields: PanelField[];
}

export interface ModuleHealth {
  module: string;
  displayName: string;
  status: HealthStatus;
  checks: HealthcheckResult[];
  healthyCount: number;
  totalCount: number;
  lastUpdated: string;
}

export interface HealthcheckResult {
  checkId: string;
  status: HealthStatus;
  message?: string | null;
  error?: string | null;
  output?: string | null;
  durationMs: number;
  timestamp: string;
  check?: Healthcheck | null;
}

export interface Healthcheck {
  id: string;
  name: string;
  description?: string | null;
  type: string;
  severity: string;
  module: string;
  tags?: string[];
  enabled: boolean;
  // Script-based checks
  script?: string | null;
  scriptPath?: string | null;
  // Nix-based checks
  nixExpr?: string | null;
  // HTTP-based checks
  httpUrl?: string | null;
  httpMethod?: string | null;
  httpExpectedStatus?: number | null;
  // TCP-based checks
  tcpHost?: string | null;
  tcpPort?: number | null;
}

export type HealthStatus =
  | "HEALTH_STATUS_UNSPECIFIED"
  | "HEALTH_STATUS_HEALTHY"
  | "HEALTH_STATUS_DEGRADED"
  | "HEALTH_STATUS_UNHEALTHY"
  | "HEALTH_STATUS_UNKNOWN"
  | "HEALTH_STATUS_DISABLED";

export interface Module {
  id: string;
  enabled: boolean;
  meta: ModuleMeta;
  source: ModuleSource;
  features: ModuleFeatures;
  requires?: string[];
  conflicts?: string[];
  priority: number;
  tags?: string[];
  configSchema?: string | null;
  panels?: ModulePanel[];
  apps?: Record<string, unknown>;
  healthcheckModule?: string | null;
  health?: ModuleHealth | null;
}

export interface ModuleConfig {
  enable?: boolean;
  settings?: Record<string, unknown>;
}

// =============================================================================
// API Response Types
// =============================================================================

export interface ModulesResponse {
  modules: Module[];
  total: number;
  enabled: number;
  lastUpdated: string;
}

export interface ModuleDetailResponse {
  module: Module;
  config: ModuleConfig;
}

// =============================================================================
// Registry Types
// =============================================================================

/** A module available in the registry (not yet installed) */
export interface RegistryModule {
  /** Unique identifier in the registry */
  id: string;
  /** Display metadata */
  meta: ModuleMeta;
  /** Features this module provides */
  features: ModuleFeatures;
  /** Module dependencies */
  requires?: string[];
  /** Conflicting modules */
  conflicts?: string[];
  /** Tags for search/filtering */
  tags?: string[];
  /** Flake URL to install from (or "builtin" for built-in modules) */
  flakeUrl: string;
  /** Module path within the flake, or enable path for built-in modules */
  flakePath?: string;
  /** Git ref (branch/tag/commit) */
  ref?: string;
  /** Number of downloads/installs (for popularity sorting) */
  downloads?: number;
  /** Star rating (0-5) */
  rating?: number;
  /** Last updated timestamp */
  updatedAt?: string;
  /** Whether this module is already installed locally */
  installed?: boolean;
  /** Whether this is a built-in module (no installation needed, just enable) */
  builtin?: boolean;
}

/** Registry source configuration */
export interface RegistrySource {
  /** Unique identifier */
  id: string;
  /** Display name */
  name: string;
  /** Registry URL (JSON manifest) */
  url: string;
  /** Whether this is the official registry */
  official?: boolean;
  /** Whether this registry is enabled */
  enabled: boolean;
}

/** Response from registry modules endpoint */
export interface RegistryModulesResponse {
  modules: RegistryModule[];
  total: number;
  sources: RegistrySource[];
  lastUpdated: string;
}

/** Request to install a module from registry */
export interface InstallModuleRequest {
  moduleId: string;
  flakeUrl: string;
  flakePath?: string;
  ref?: string;
}

/** Response from install module endpoint */
export interface InstallModuleResponse {
  success: boolean;
  message: string;
  /** Generated Nix code to add to flake.nix */
  flakeInputCode?: string;
  /** Generated Nix code to add to devenv.nix */
  moduleImportCode?: string;
}

// =============================================================================
// UI State Types
// =============================================================================

export interface ModuleFilters {
  search: string;
  category: string | null;
  showDisabled: boolean;
  sourceType: string | null;
}

export const MODULE_CATEGORIES = [
  { value: "unspecified", label: "Uncategorized" },
  { value: "infrastructure", label: "Infrastructure" },
  { value: "ci-cd", label: "CI/CD" },
  { value: "database", label: "Database" },
  { value: "secrets", label: "Secrets" },
  { value: "deployment", label: "Deployment" },
  { value: "development", label: "Development" },
  { value: "monitoring", label: "Monitoring" },
  { value: "integration", label: "Integration" },
  { value: "language", label: "Language" },
  { value: "service", label: "Service" },
] as const;

export const SOURCE_TYPES = [
  { value: "builtin", label: "Built-in" },
  { value: "local", label: "Local" },
  { value: "flake-input", label: "Flake Input" },
  { value: "registry", label: "Registry" },
] as const;

// =============================================================================
// Helper Functions
// =============================================================================

export function getCategoryLabel(category: string): string {
  const found = MODULE_CATEGORIES.find((c) => c.value === category);
  return found?.label ?? category;
}

export function getSourceLabel(type: string): string {
  const found = SOURCE_TYPES.find((s) => s.value === type);
  return found?.label ?? type;
}

export function getHealthStatusColor(status: HealthStatus): string {
  switch (status) {
    case "HEALTH_STATUS_HEALTHY":
      return "text-green-500";
    case "HEALTH_STATUS_DEGRADED":
      return "text-yellow-500";
    case "HEALTH_STATUS_UNHEALTHY":
      return "text-red-500";
    case "HEALTH_STATUS_UNKNOWN":
    case "HEALTH_STATUS_UNSPECIFIED":
      return "text-muted-foreground";
    case "HEALTH_STATUS_DISABLED":
      return "text-muted-foreground";
    default:
      return "text-muted-foreground";
  }
}

export function getHealthStatusLabel(status: HealthStatus): string {
  switch (status) {
    case "HEALTH_STATUS_HEALTHY":
      return "Healthy";
    case "HEALTH_STATUS_DEGRADED":
      return "Degraded";
    case "HEALTH_STATUS_UNHEALTHY":
      return "Unhealthy";
    case "HEALTH_STATUS_UNKNOWN":
      return "Unknown";
    case "HEALTH_STATUS_DISABLED":
      return "Disabled";
    default:
      return "Unknown";
  }
}
