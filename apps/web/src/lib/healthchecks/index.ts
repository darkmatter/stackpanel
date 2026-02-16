/**
 * Healthchecks Module
 *
 * Provides components and hooks for displaying module health status
 * using a "traffic light" metaphor (green/yellow/red).
 *
 * Components:
 *   - TrafficLight: Icon-based health status indicator
 *   - TrafficLightDot: Simple dot-style indicator
 *   - TrafficLightBadge: Badge-style indicator with label
 *   - HealthSummaryPanel: Full panel with all module health statuses
 *
 * Hooks:
 *   - useHealthchecks: Fetch all health data
 *   - useModuleHealth: Fetch health for a specific module
 *   - useHealthcheckResult: Fetch a specific check result
 *
 * Usage:
 *   import { TrafficLight, useHealthchecks } from '@/lib/healthchecks';
 *
 *   function MyComponent() {
 *     const { data, isLoading, runChecks } = useHealthchecks();
 *     return <TrafficLight status={data?.overallStatus ?? 'HEALTH_STATUS_UNKNOWN'} />;
 *   }
 */

// Types
export type {
  HealthStatus,
  HealthcheckType,
  HealthcheckSeverity,
  Healthcheck,
  HealthcheckResult,
  ModuleHealth,
  HealthSummary,
  HealthchecksResponse,
  HealthchecksUpdatedEvent,
  HealthchecksRunningEvent,
  HealthcheckResultEvent,
  TrafficLightProps,
  ModuleHealthCardProps,
  HealthSummaryPanelProps,
  StatusDisplayProps,
} from "./types";

// Constants
export { STATUS_DISPLAY } from "./types";

// Components
export {
  TrafficLight,
  TrafficLightDot,
  TrafficLightBadge,
} from "./traffic-light";

export {
  HealthSummaryPanel,
  HealthSummaryPanelView,
} from "./health-summary-panel";

// Hooks
export {
  useHealthchecks,
  useModuleHealth,
  useHealthcheckResult,
  getOverallStatus,
  countModulesByStatus,
} from "./use-healthchecks";
