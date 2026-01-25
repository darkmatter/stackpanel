/**
 * Status Panel Component
 *
 * Displays status metrics for an extension with icons and values.
 * Supports ok/warning/error status indicators.
 */

import { Card, CardContent, CardHeader, CardTitle } from "@ui/card";
import { AlertCircle, CheckCircle, XCircle } from "lucide-react";
import type { StatusMetric, StatusPanelProps } from "../types";

const statusIcons = {
	ok: CheckCircle,
	warning: AlertCircle,
	error: XCircle,
} as const;

const statusColors = {
	ok: "text-green-500",
	warning: "text-yellow-500",
	error: "text-destructive",
} as const;

export function StatusPanel({ extension, metrics }: StatusPanelProps & { allApps?: Record<string, unknown> }) {
	if (!metrics || metrics.length === 0) {
		return (
			<Card>
				<CardHeader>
					<CardTitle>{extension.name} Status</CardTitle>
				</CardHeader>
				<CardContent>
					<p className="text-sm text-muted-foreground">
						No status metrics available.
					</p>
				</CardContent>
			</Card>
		);
	}

	return (
		<Card>
			<CardHeader>
				<CardTitle>{extension.name} Status</CardTitle>
			</CardHeader>
			<CardContent>
				<dl className="grid grid-cols-1 gap-4 sm:grid-cols-2">
					{metrics.map((metric, index) => (
						<MetricItem key={`${metric.label}-${index}`} metric={metric} />
					))}
				</dl>
			</CardContent>
		</Card>
	);
}

/**
 * Individual metric item with status icon
 */
function MetricItem({ metric }: { metric: StatusMetric }) {
	const status = metric.status || "ok";
	const Icon = statusIcons[status];
	const colorClass = statusColors[status];

	return (
		<div className="flex items-center gap-3">
			<Icon className={`h-4 w-4 flex-shrink-0 ${colorClass}`} />
			<div className="flex min-w-0 flex-1 items-baseline justify-between gap-2">
				<dt className="truncate text-sm text-muted-foreground">
					{metric.label}
				</dt>
				<dd className="font-medium">{metric.value}</dd>
			</div>
		</div>
	);
}
