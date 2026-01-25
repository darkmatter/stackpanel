"use client";

import { Badge } from "@ui/badge";
import { Button } from "@ui/button";
import { Card, CardContent, CardHeader } from "@ui/card";
import { Input } from "@ui/input";
import {
	Select,
	SelectContent,
	SelectItem,
	SelectTrigger,
	SelectValue,
} from "@ui/select";
import {
	Tooltip,
	TooltipContent,
	TooltipProvider,
	TooltipTrigger,
} from "@ui/tooltip";
import {
	ChevronDown,
	ChevronRight,
	Loader2,
	Package,
	Play,
	Search,
} from "lucide-react";
import { useMemo, useState } from "react";
import { useTurboPackages } from "@/lib/use-agent";
import { PanelHeader } from "./shared/panel-header";

/**
 * TasksPanel displays tasks discovered from the turbo package graph.
 * Tasks are the source of truth from turbo.json and can be run on packages.
 */
export function TasksPanel() {
	const { packages, allTasks, isLoading, isError, error, refetch } =
		useTurboPackages();

	const [searchQuery, setSearchQuery] = useState("");
	const [selectedPackage, setSelectedPackage] = useState<string | null>(null);
	const [expandedTasks, setExpandedTasks] = useState<Set<string>>(
		new Set(["dev", "build", "test"]),
	);

	// Filter tasks based on search
	const filteredTasks = useMemo(() => {
		if (!searchQuery) return allTasks;
		return allTasks.filter((task) =>
			task.toLowerCase().includes(searchQuery.toLowerCase()),
		);
	}, [allTasks, searchQuery]);

	// Get packages that have a specific task, optionally filtered
	const getPackagesWithTask = (taskName: string) => {
		return packages.filter((pkg) => {
			const hasTask = pkg.tasks.some((t) => t.name === taskName);
			if (!hasTask) return false;
			if (selectedPackage && pkg.name !== selectedPackage) return false;
			return true;
		});
	};

	// Get counts for display
	const taskCounts = useMemo(() => {
		const counts: Record<string, number> = {};
		for (const task of allTasks) {
			counts[task] = getPackagesWithTask(task).length;
		}
		return counts;
	}, [allTasks, packages, selectedPackage]);

	const toggleTask = (task: string) => {
		setExpandedTasks((prev) => {
			const next = new Set(prev);
			if (next.has(task)) {
				next.delete(task);
			} else {
				next.add(task);
			}
			return next;
		});
	};

	if (isLoading) {
		return (
			<Card>
				<CardContent className="flex items-center justify-center py-12">
					<Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
				</CardContent>
			</Card>
		);
	}

	if (isError) {
		return (
			<Card className="border-destructive/50">
				<CardContent className="py-6">
					<p className="text-center text-destructive">
						Failed to load tasks: {error?.message ?? "Unknown error"}
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
					title="Tasks"
					description={`${allTasks.length} task${allTasks.length !== 1 ? "s" : ""} discovered from turbo.json across ${packages.length} package${packages.length !== 1 ? "s" : ""}`}
					guideKey="tasks"
					actions={
						<Button variant="outline" size="sm" onClick={() => refetch()}>
							Refresh
						</Button>
					}
				/>

				{/* Search and Filter */}
				<div className="flex gap-2">
					<div className="relative flex-1">
						<Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
						<Input
							placeholder="Search tasks..."
							value={searchQuery}
							onChange={(e) => setSearchQuery(e.target.value)}
							className="pl-9"
						/>
					</div>
					<Select
						value={selectedPackage ?? "all"}
						onValueChange={(value) =>
							setSelectedPackage(value === "all" ? null : value)
						}
					>
						<SelectTrigger className="w-48">
							<SelectValue placeholder="All packages" />
						</SelectTrigger>
						<SelectContent>
							<SelectItem value="all">All packages</SelectItem>
							{packages.map((pkg) => (
								<SelectItem key={pkg.name} value={pkg.name}>
									{pkg.name}
								</SelectItem>
							))}
						</SelectContent>
					</Select>
				</div>

				{/* Tasks List */}
				<div className="space-y-2">
					{filteredTasks.length === 0 ? (
						<Card>
							<CardContent className="py-8 text-center">
								<Play className="mx-auto h-12 w-12 text-muted-foreground/50" />
								<p className="mt-2 text-muted-foreground">
									{searchQuery
										? "No tasks match your search"
										: "No tasks discovered from turbo.json"}
								</p>
							</CardContent>
						</Card>
					) : (
						filteredTasks.map((task) => {
							const count = taskCounts[task] ?? 0;
							const isExpanded = expandedTasks.has(task);
							const packagesWithTask = getPackagesWithTask(task);

							// Skip if filtering by package and this task isn't in that package
							if (selectedPackage && count === 0) return null;

							return (
								<Card key={task}>
									<CardHeader
										className="cursor-pointer py-3"
										onClick={() => toggleTask(task)}
									>
										<div className="flex items-center justify-between">
											<div className="flex items-center gap-2">
												{isExpanded ? (
													<ChevronDown className="h-4 w-4 text-muted-foreground" />
												) : (
													<ChevronRight className="h-4 w-4 text-muted-foreground" />
												)}
												<Play className="h-4 w-4 text-accent" />
												<code className="rounded bg-secondary px-2 py-0.5 font-mono text-sm font-medium">
													{task}
												</code>
												<Badge variant="secondary" className="text-xs">
													{count} package{count !== 1 ? "s" : ""}
												</Badge>
											</div>
											<Tooltip>
												<TooltipTrigger asChild>
													<code className="text-muted-foreground text-xs">
														turbo run {task}
													</code>
												</TooltipTrigger>
												<TooltipContent>
													Run this task across all packages
												</TooltipContent>
											</Tooltip>
										</div>
									</CardHeader>

									{isExpanded && packagesWithTask.length > 0 && (
										<CardContent className="pt-0">
											<div className="rounded-lg border border-border bg-secondary/30 p-3">
												<div className="mb-2 text-muted-foreground text-xs font-medium uppercase tracking-wide">
													Available in packages:
												</div>
												<div className="flex flex-wrap gap-2">
													{packagesWithTask.map((pkg) => (
														<Tooltip key={pkg.name}>
															<TooltipTrigger asChild>
																<div className="flex items-center gap-1.5 rounded-md bg-background px-2 py-1 text-sm">
																	<Package className="h-3 w-3 text-muted-foreground" />
																	<span className="font-mono">{pkg.name}</span>
																</div>
															</TooltipTrigger>
															<TooltipContent>
																<div className="text-xs">
																	<div className="font-medium">{pkg.name}</div>
																	<div className="text-muted-foreground">
																		{pkg.path}
																	</div>
																	<div className="mt-1 font-mono text-accent">
																		turbo run {task} --filter={pkg.name}
																	</div>
																</div>
															</TooltipContent>
														</Tooltip>
													))}
												</div>
											</div>
										</CardContent>
									)}
								</Card>
							);
						})
					)}
				</div>

				{/* Info Card */}
				<Card className="border-accent/30 bg-accent/5">
					<CardContent className="py-4">
						<div className="flex items-start gap-3">
							<Play className="mt-0.5 h-5 w-5 text-accent" />
							<div className="text-sm">
								<p className="font-medium text-foreground">
									Tasks are discovered from turbo.json
								</p>
								<p className="mt-1 text-muted-foreground">
									Tasks shown here are automatically detected from your
									monorepo&apos;s turbo configuration. Edit your{" "}
									<code className="rounded bg-secondary px-1 py-0.5 text-xs">
										turbo.json
									</code>{" "}
									or package{" "}
									<code className="rounded bg-secondary px-1 py-0.5 text-xs">
										package.json
									</code>{" "}
									files to modify available tasks.
								</p>
							</div>
						</div>
					</CardContent>
				</Card>
			</div>
		</TooltipProvider>
	);
}
