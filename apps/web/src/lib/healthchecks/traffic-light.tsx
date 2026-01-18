/**
 * TrafficLight Component
 *
 * A visual indicator component that displays health status using a
 * traffic light metaphor (green/yellow/red/grey).
 *
 * Usage:
 *   <TrafficLight status="HEALTH_STATUS_HEALTHY" />
 *   <TrafficLight status="HEALTH_STATUS_DEGRADED" size="lg" pulse />
 *   <TrafficLight status="HEALTH_STATUS_UNHEALTHY" label="Database" />
 */

import { cn } from "@/lib/utils";
import {
  AlertCircle,
  CheckCircle,
  HelpCircle,
  MinusCircle,
  XCircle,
} from "lucide-react";
import type { HealthStatus, TrafficLightProps } from "./types";
import { STATUS_DISPLAY } from "./types";

// Size configurations
const sizeConfig = {
  sm: {
    container: "h-4 w-4",
    icon: 14,
    dot: "h-2 w-2",
    text: "text-xs",
    gap: "gap-1",
  },
  md: {
    container: "h-5 w-5",
    icon: 18,
    dot: "h-3 w-3",
    text: "text-sm",
    gap: "gap-1.5",
  },
  lg: {
    container: "h-6 w-6",
    icon: 22,
    dot: "h-4 w-4",
    text: "text-base",
    gap: "gap-2",
  },
} as const;

// Icon components for each status type
const StatusIcon = {
  check: CheckCircle,
  warning: AlertCircle,
  error: XCircle,
  unknown: HelpCircle,
  disabled: MinusCircle,
} as const;

// Default display for unknown statuses
const DEFAULT_DISPLAY = STATUS_DISPLAY.HEALTH_STATUS_UNKNOWN;

/**
 * Get the appropriate icon component for a health status
 */
function getStatusIcon(status: HealthStatus) {
  const display = STATUS_DISPLAY[status] ?? DEFAULT_DISPLAY;
  return StatusIcon[display.icon];
}

/**
 * TrafficLight Component
 *
 * Displays a colored indicator representing health status.
 *
 * @param status - The health status to display
 * @param size - Size of the indicator (sm, md, lg)
 * @param pulse - Whether to show a pulse animation (for healthy status)
 * @param label - Optional label to show next to the indicator
 * @param onClick - Optional click handler
 */
export function TrafficLight({
  status,
  size = "md",
  pulse = false,
  label,
  onClick,
}: TrafficLightProps) {
  const display = STATUS_DISPLAY[status] ?? DEFAULT_DISPLAY;
  const config = sizeConfig[size];
  const Icon = getStatusIcon(status);

  const isClickable = !!onClick;
  const isHealthy = status === "HEALTH_STATUS_HEALTHY";
  const showPulse = pulse && isHealthy;

  const indicator = (
    <div className={cn("relative", config.container)}>
      {/* Pulse animation ring */}
      {showPulse && (
        <span
          className={cn(
            "absolute inset-0 rounded-full opacity-75",
            display.bgClass,
            "animate-ping",
          )}
        />
      )}
      {/* Main icon */}
      <Icon
        size={config.icon}
        className={cn(
          "relative",
          display.colorClass,
          isClickable && "transition-transform hover:scale-110",
        )}
      />
    </div>
  );

  // If no label, just return the indicator
  if (!label) {
    if (isClickable) {
      return (
        <button
          type="button"
          onClick={onClick}
          className={cn(
            "inline-flex items-center justify-center",
            "rounded-md p-1",
            "hover:bg-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring",
          )}
          aria-label={`Health status: ${display.label}`}
        >
          {indicator}
        </button>
      );
    }
    return indicator;
  }

  // With label
  const content = (
    <div className={cn("inline-flex items-center", config.gap)}>
      {indicator}
      <span className={cn(config.text, "text-foreground")}>{label}</span>
    </div>
  );

  if (isClickable) {
    return (
      <button
        type="button"
        onClick={onClick}
        className={cn(
          "inline-flex items-center",
          "rounded-md px-2 py-1",
          "hover:bg-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring",
        )}
        aria-label={`${label}: ${display.label}`}
      >
        {content}
      </button>
    );
  }

  return content;
}

/**
 * TrafficLightDot Component
 *
 * A simpler dot-style indicator without icons, useful for inline display.
 */
export function TrafficLightDot({
  status,
  size = "md",
  pulse = false,
  className,
}: {
  status: HealthStatus;
  size?: "sm" | "md" | "lg";
  pulse?: boolean;
  className?: string;
}) {
  const display = STATUS_DISPLAY[status] ?? DEFAULT_DISPLAY;
  const config = sizeConfig[size];
  const isHealthy = status === "HEALTH_STATUS_HEALTHY";
  const showPulse = pulse && isHealthy;

  return (
    <span
      className={cn(
        "relative inline-flex items-center justify-center",
        config.dot,
        className,
      )}
    >
      {showPulse && (
        <span
          className={cn(
            "absolute inset-0 rounded-full opacity-75",
            display.bgClass,
            "animate-ping",
          )}
        />
      )}
      <span
        className={cn("relative rounded-full", config.dot, display.bgClass)}
      />
    </span>
  );
}

/**
 * TrafficLightBadge Component
 *
 * A badge-style indicator with status text.
 */
export function TrafficLightBadge({
  status,
  size = "md",
  showLabel = true,
  className,
}: {
  status: HealthStatus;
  size?: "sm" | "md" | "lg";
  showLabel?: boolean;
  className?: string;
}) {
  const display = STATUS_DISPLAY[status] ?? DEFAULT_DISPLAY;
  const config = sizeConfig[size];

  return (
    <span
      className={cn(
        "inline-flex items-center rounded-full px-2 py-0.5",
        "border",
        status === "HEALTH_STATUS_HEALTHY" &&
          "border-green-200 bg-green-50 text-green-700 dark:border-green-800 dark:bg-green-950 dark:text-green-400",
        status === "HEALTH_STATUS_DEGRADED" &&
          "border-yellow-200 bg-yellow-50 text-yellow-700 dark:border-yellow-800 dark:bg-yellow-950 dark:text-yellow-400",
        status === "HEALTH_STATUS_UNHEALTHY" &&
          "border-red-200 bg-red-50 text-red-700 dark:border-red-800 dark:bg-red-950 dark:text-red-400",
        (status === "HEALTH_STATUS_UNKNOWN" ||
          status === "HEALTH_STATUS_UNSPECIFIED" ||
          status === "HEALTH_STATUS_DISABLED") &&
          "border-muted bg-muted/50 text-muted-foreground",
        config.gap,
        className,
      )}
    >
      <TrafficLightDot status={status} size="sm" />
      {showLabel && <span className={config.text}>{display.label}</span>}
    </span>
  );
}

export default TrafficLight;
