"use client";

import { Button } from "@ui/button";
import { Card, CardContent } from "@ui/card";
import { Input } from "@ui/input";
import {
	TooltipProvider,
} from "@ui/tooltip";
import {
	Loader2,
	Play,
	Search,
} from "lucide-react";
import { useHealthchecks } from "@/lib/healthchecks/use-healthchecks";
import { PanelHeader } from "./shared/panel-header";
import { HealthSummaryPanelView } from "@/lib/healthchecks/health-summary-panel";

/**
 * ChecksPanel displays checks discovered from the turbo package graph.
 * Checks are the source of truth from turbo.json and can be run on packages.
 */
export function ChecksPanel() {
	const {
		data: summary,
		isLoading,
		error,
		isRefreshing,
		runningCheckIds,
		refetch,
		runChecks,
	} = useHealthchecks({ enabled: true });



	// Only show the full-page loader on the very first load (no data yet).
	// Subsequent refetches/re-runs keep the existing UI mounted so that
	// collapsible open/closed state is preserved.
	if (isLoading && !summary) {
		return (
			<Card>
				<CardContent className="flex items-center justify-center py-12">
					<Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
				</CardContent>
			</Card>
		);
	}

	if (error && !summary) {
		return (
			<Card className="border-destructive/50">
				<CardContent className="py-6">
					<p className="text-center text-destructive">
						Failed to load checks: {error}
					</p>
					<div className="mt-4 flex justify-center">
						<Button variant="outline" onClick={() => refetch()}>
							Retry
						</Button>
					</div>
				</CardContent>
			</Card>
		);
	}

	return (
		<TooltipProvider>
			<div className="space-y-4">
				<PanelHeader
					title="Checks"
					description={`${Object.keys(summary?.modules ?? {}).length} module${Object.keys(summary?.modules ?? {}).length !== 1 ? "s" : ""} monitored`}
					actions={
						<Button variant="outline" size="sm" onClick={() => refetch()}>
							Refresh
						</Button>
					}
				/>

				{/* Search and Filter */}
				<div className="flex gap-2 flex-col">
					<div className="relative flex-1">
						<Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
						<Input
							placeholder="Search checks..."
							className="pl-9"
						/>
					</div>
					<HealthSummaryPanelView summary={summary ?? null} isLoading={isLoading} error={error ?? undefined} isRefreshing={isRefreshing} runningCheckIds={runningCheckIds} onRunChecks={runChecks} />

					{/* Info Card */}
					<Card className="border-accent/30 bg-accent/5">
						<CardContent className="py-4">
							<div className="flex items-start gap-3">
								<Play className="mt-0.5 h-5 w-5 text-accent" />
								<div className="text-sm">
									<p className="font-medium text-foreground">
										Checks are discovered from healthchecks.json
									</p>
									<p className="mt-1 text-muted-foreground">
										Checks shown here are automatically detected from your
										monorepo&apos;s healthchecks configuration. Edit your{" "}
										<code className="rounded bg-secondary px-1 py-0.5 text-xs">
											healthchecks.json
										</code>{" "}
										or package{" "}
										<code className="rounded bg-secondary px-1 py-0.5 text-xs">
											package.json
										</code>{" "}
										files to modify available checks.
									</p>
								</div>
							</div>
						</CardContent>
					</Card>
				</div>
			</div>
		</TooltipProvider>
	);
}
