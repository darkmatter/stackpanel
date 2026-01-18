"use client";

import {
	AlertTriangle,
	Check,
	CheckCircle2,
	Circle,
	Clock,
	Loader2,
	Lock,
	type LucideIcon,
	XCircle,
} from "lucide-react";
import type * as React from "react";
import { cn } from "@/lib/utils";

// =============================================================================
// Status Types
// =============================================================================

export type StatusVariant =
	| "success"
	| "warning"
	| "error"
	| "info"
	| "muted"
	| "pending";

export interface StatusConfig {
	icon?: LucideIcon;
	text: string;
	variant: StatusVariant;
}

// =============================================================================
// Variant Styles
// =============================================================================

const variantStyles: Record<StatusVariant, string> = {
	success:
		"bg-green-500/10 text-green-600 dark:bg-green-400/10 dark:text-green-400",
	warning:
		"bg-yellow-500/10 text-yellow-600 dark:bg-yellow-400/10 dark:text-yellow-400",
	error: "bg-red-500/10 text-red-600 dark:bg-red-400/10 dark:text-red-400",
	info: "bg-blue-500/10 text-blue-600 dark:bg-blue-400/10 dark:text-blue-400",
	muted: "bg-muted text-muted-foreground",
	pending:
		"bg-orange-500/10 text-orange-600 dark:bg-orange-400/10 dark:text-orange-400",
};

// =============================================================================
// Default Presets
// =============================================================================

/**
 * Preset status configurations for common use cases.
 */
export const statusPresets = {
	// General statuses
	success: { icon: Check, text: "Success", variant: "success" as const },
	warning: {
		icon: AlertTriangle,
		text: "Warning",
		variant: "warning" as const,
	},
	error: { icon: XCircle, text: "Error", variant: "error" as const },
	pending: { icon: Clock, text: "Pending", variant: "pending" as const },
	loading: { icon: Loader2, text: "Loading", variant: "info" as const },
	disabled: { icon: Circle, text: "Disabled", variant: "muted" as const },

	// File statuses
	fileOk: { icon: Check, text: "OK", variant: "success" as const },
	fileMissing: {
		icon: AlertTriangle,
		text: "Missing",
		variant: "pending" as const,
	},
	fileStale: {
		icon: AlertTriangle,
		text: "Stale",
		variant: "warning" as const,
	},
	fileDisabled: { text: "Disabled", variant: "muted" as const },

	// Step statuses
	complete: {
		icon: CheckCircle2,
		text: "Complete",
		variant: "success" as const,
	},
	incomplete: {
		icon: Circle,
		text: "Not configured",
		variant: "muted" as const,
	},
	inProgress: { icon: Loader2, text: "In progress", variant: "info" as const },
	optional: { icon: Clock, text: "Optional", variant: "warning" as const },
	blocked: {
		icon: Lock,
		text: "Requires previous step",
		variant: "muted" as const,
	},

	// Service statuses
	running: { icon: Check, text: "Running", variant: "success" as const },
	stopped: { icon: Circle, text: "Stopped", variant: "muted" as const },
	starting: { icon: Loader2, text: "Starting", variant: "info" as const },
	stopping: { icon: Loader2, text: "Stopping", variant: "warning" as const },
} satisfies Record<string, StatusConfig>;

// =============================================================================
// Component
// =============================================================================

interface StatusBadgeProps extends React.ComponentProps<"span"> {
	/** Status configuration or preset key */
	status: StatusConfig | keyof typeof statusPresets;
	/** Whether to show only the icon (no text) */
	iconOnly?: boolean;
	/** Size variant */
	size?: "sm" | "default";
}

/**
 * A flexible status badge component for displaying various statuses.
 *
 * @example
 * ```tsx
 * // Using preset
 * <StatusBadge status="success" />
 *
 * // Using custom config
 * <StatusBadge status={{ icon: Star, text: "Featured", variant: "info" }} />
 *
 * // Icon only
 * <StatusBadge status="running" iconOnly />
 * ```
 */
function StatusBadge({
	status,
	iconOnly = false,
	size = "default",
	className,
	...props
}: StatusBadgeProps) {
	// Resolve config from preset or use directly
	const config: StatusConfig =
		typeof status === "string" ? statusPresets[status] : status;

	const Icon = config.icon;
	const isSpinning = Icon === Loader2;

	const sizeClasses = {
		sm: "text-xs px-1.5 py-0.5",
		default: "text-xs px-2 py-0.5",
	};

	const iconSizes = {
		sm: "h-2.5 w-2.5",
		default: "h-3 w-3",
	};

	return (
		<span
			className={cn(
				"inline-flex items-center gap-1 rounded-full font-medium",
				variantStyles[config.variant],
				sizeClasses[size],
				className,
			)}
			{...props}
		>
			{Icon && (
				<Icon className={cn(iconSizes[size], isSpinning && "animate-spin")} />
			)}
			{!iconOnly && config.text}
		</span>
	);
}

export { StatusBadge };
export type { StatusBadgeProps };
