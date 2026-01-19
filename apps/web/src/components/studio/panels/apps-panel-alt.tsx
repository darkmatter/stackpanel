"use client";

import { VariableType } from "@stackpanel/proto";
import { Badge } from "@ui/badge";
import { Button } from "@ui/button";
import { Input } from "@ui/input";
import {
	Tooltip,
	TooltipContent,
	TooltipProvider,
	TooltipTrigger,
} from "@ui/tooltip";
import {
	ChevronDown,
	ChevronRight,
	Circle,
	FolderOpen,
	Loader2,
	Pencil,
	Trash2,
} from "lucide-react";
import { useCallback, useEffect, useMemo, useState } from "react";
import {
	type ProcessComposeStatusResponse,
	type TurboPackage,
} from "@/lib/agent";
import { useAgentContext, useAgentClient } from "@/lib/agent-provider";
import { useAgentSSEEvent } from "@/lib/agent-sse-provider";
import type { App } from "@/lib/types";
import {
	useApps,
	useNixConfig,
	useVariables,
} from "@/lib/use-nix-config";
import { AddAppDialog } from "./apps/add-app-dialog";
import { AppVariablesSection } from "./apps/app-variables-section";
import { useAppMutations } from "./apps/hooks";
import type { DisplayVariable, TaskWithCommand } from "./apps/types";
import {
	computeStablePort,
	flattenEnvironmentVariables,
	getEnvironmentNames,
} from "./apps/utils";
import { PanelHeader } from "./shared/panel-header";

export function AppsPanelAlt() {
	const { token } = useAgentContext();
	const agentClient = useAgentClient();
	const { data: rawApps, isLoading, error, refetch } = useApps();
	const { data: nixConfig } = useNixConfig();
	const { data: allVariables } = useVariables();

	// Get project name from config, fallback to "stackpanel"
	const projectName = nixConfig?.projectName ?? "stackpanel";

	// Transform apps data to include id, stablePort, and isRunning fields
	const resolvedApps = useMemo(() => {
		if (!rawApps) return null;
		const result: Record<string, App & { id: string; stablePort: number; isRunning: boolean }> = {};
		for (const [id, app] of Object.entries(rawApps)) {
			result[id] = {
				...app,
				id,
				stablePort: app.port ?? 3000,
				isRunning: false, // Will be updated from process-compose status
			};
		}
		return result;
	}, [rawApps]);

	// Turbo package graph state - source of truth for available tasks
	const [packageGraph, setPackageGraph] = useState<TurboPackage[]>([]);
	const [_isLoadingPackages, setIsLoadingPackages] = useState(false);

	// Process-compose state - for tracking running processes
	const [processComposeStatus, setProcessComposeStatus] =
		useState<ProcessComposeStatusResponse | null>(null);

	const [expandedApp, setExpandedApp] = useState<string | null>(null);
	const [isDeleting, setIsDeleting] = useState<string | null>(null);
	const [editingTask, setEditingTask] = useState<{
		appId: string;
		taskName: string;
	} | null>(null);
	const [taskCommandOverride, setTaskCommandOverride] = useState("");

	// Use the extracted mutations hook
	const {
		handleAddVariableToApp,
		handleUpdateVariableInApp,
		handleUpdateEnvironmentsForApp,
		handleDeleteVariableFromApp,
		handleDeleteApp,
	} = useAppMutations({
		token,
		resolvedApps: resolvedApps ?? undefined,
		refetch,
	});

	const environmentOptions = useMemo(() => {
		const defaults = ["dev", "staging", "prod"];
		const appDefined = Object.values(resolvedApps ?? {}).flatMap((app) =>
			getEnvironmentNames(app.environments),
		);
		return Array.from(new Set([...defaults, ...appDefined]));
	}, [resolvedApps]);

	// Available variables for the inline add UI
	const availableVariablesForAdd = useMemo(() => {
		if (!allVariables) return [];
		return Object.entries(allVariables).map(([id, variable]) => ({
			id,
			key: variable.key || id,
			type: variable.type ?? null,
		}));
	}, [allVariables]);

	// Fetch turbo package graph
	const fetchPackageGraph = useCallback(async () => {
		if (!token) return;

		setIsLoadingPackages(true);
		try {
			const client = agentClient;
			const packages = await client.getPackageGraph({ excludeRoot: true });
			setPackageGraph(packages);
		} catch (err) {
			console.error("Failed to fetch package graph:", err);
		} finally {
			setIsLoadingPackages(false);
		}
	}, [token]);

	// Fetch process-compose status
	const fetchProcessComposeStatus = useCallback(async () => {
		if (!token) return;

		try {
			const client = agentClient;
			const status = await client.getProcessComposeProcesses();
			setProcessComposeStatus(status);
		} catch (err) {
			console.error("Failed to fetch process-compose status:", err);
		}
	}, [token]);

	// Initial fetch
	useEffect(() => {
		fetchPackageGraph();
		fetchProcessComposeStatus();
	}, [fetchPackageGraph, fetchProcessComposeStatus]);

	// Subscribe to turbo.changed events for auto-refetch
	useAgentSSEEvent("turbo.changed", () => {
		fetchPackageGraph();
	});

	// Subscribe to config.changed events for auto-refetch
	useAgentSSEEvent("config.changed", () => {
		refetch();
	});

	// Get turbo tasks for a specific app path from the package graph
	const getTurboTasksForApp = useCallback(
		(appPath: string): Map<string, string> => {
			const pkg = packageGraph.find((p) => p.path === appPath);
			if (!pkg) return new Map();

			const taskMap = new Map<string, string>();
			for (const t of pkg.tasks) {
				taskMap.set(t.name, `turbo run ${t.name} --filter=${pkg.name}`);
			}
			return taskMap;
		},
		[packageGraph],
	);

	// Get all tasks for an app, merging turbo tasks with any configured overrides
	const getTasksForApp = useCallback(
		(app: App): TaskWithCommand[] => {
			const turboTasks = getTurboTasksForApp(app.path);
			const configuredTasks = app.tasks ?? {};

			// Start with turbo tasks
			const tasks: TaskWithCommand[] = Array.from(turboTasks.entries()).map(
				([name, command]) => {
					const turboCommand = configuredTasks[name]?.command;
					return {
						name,
						command: turboCommand ?? command,
						isOverridden: !!turboCommand,
					};
				},
			);

			// Add any configured tasks that aren't in turbo
			for (const [name, task] of Object.entries(configuredTasks)) {
				if (!turboTasks.has(name)) {
					tasks.push({
						name,
						command: task.command,
						isOverridden: true,
					});
				}
			}

			return tasks;
		},
		[getTurboTasksForApp],
	);

	// Create a set of running process names from process-compose
	const runningProcesses = useMemo(() => {
		if (!processComposeStatus?.running || !processComposeStatus.processes) {
			return new Set<string>();
		}
		return new Set(
			processComposeStatus.processes
				.filter((p) => p.is_running)
				.map((p) => p.name),
		);
	}, [processComposeStatus]);

	// Convert resolved apps to display format
	const apps = useMemo(() => {
		if (!resolvedApps) return [];

		return Object.entries(resolvedApps).map(([appId, app]) => {
			const tasks = getTasksForApp(app);

			// Compute stable port for this app
			const stablePort = computeStablePort(projectName, appId);

			// Convert environments to display format - flatten variables from all environments
			const flattenedVars = flattenEnvironmentVariables(app.environments);
			const appVariables: DisplayVariable[] = flattenedVars.map((mapping) => {
				const variableId = mapping.variableId;
				const variable = variableId ? allVariables?.[variableId] : undefined;
				const type = variable?.type ?? null;
				const isSecret = type === VariableType.SECRET;
				return {
					envKey: mapping.envKey,
					variableId,
					variableKey: variable?.key ?? mapping.envKey,
					type,
					description: variable?.description ?? "",
					value: mapping.literalValue ?? variable?.value,
					environments: mapping.environments,
					isSecret,
				};
			});

			// Split by secret flag
			const secrets = appVariables.filter((v) => v.isSecret);
			const variables = appVariables.filter((v) => !v.isSecret);

			// Check if this app is running in process-compose
			// Process names match app IDs (e.g., "web", "server")
			const isRunning = runningProcesses.has(appId);

			return {
				id: appId,
				name: app.name,
				path: app.path,
				domain: app.domain ?? "",
				type: app.type,
				port: app.port ?? stablePort,
				stablePort,
				description: app.description,
				environments: getEnvironmentNames(app.environments),
				tasks,
				secrets,
				variables,
				isRunning,
				_resolved: app,
			};
		});
	}, [
		resolvedApps,
		getTasksForApp,
		projectName,
		allVariables,
		runningProcesses,
	]);

	// Auto-expand first app if none expanded
	useEffect(() => {
		if (apps.length > 0 && !expandedApp) {
			setExpandedApp(apps[0].id);
		}
	}, [apps, expandedApp]);

	const handleDelete = async (appId: string) => {
		setIsDeleting(appId);
		try {
			await handleDeleteApp(appId);
		} finally {
			setIsDeleting(null);
		}
	};

	const handleTaskEdit = (appId: string, taskName: string, command: string) => {
		setEditingTask({ appId, taskName });
		setTaskCommandOverride(command);
	};

	const handleTaskSave = async () => {
		if (!editingTask) return;
		// TODO: Save task command override to config
		setEditingTask(null);
		setTaskCommandOverride("");
	};

	const handleTaskCancel = () => {
		setEditingTask(null);
		setTaskCommandOverride("");
	};

	const totalApps = apps.length;
	const totalTasks = apps.reduce((acc, app) => acc + app.tasks.length, 0);
	const totalVariables = apps.reduce(
		(acc, app) => acc + app.variables.length + app.secrets.length,
		0,
	);

	if (isLoading) {
		return (
			<div className="flex items-center justify-center py-12">
				<Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
			</div>
		);
	}

	if (error) {
		return (
			<div className="rounded-lg border border-destructive/30 bg-destructive/5 p-4">
				<p className="text-destructive text-sm">
					Error loading apps: {error.message}
				</p>
			</div>
		);
	}

	return (
		<TooltipProvider>
			<div className="space-y-4">
				<PanelHeader
					title="Apps"
					description={`${totalApps} apps • ${totalTasks} tasks • ${totalVariables} variables`}
					guideKey="apps"
					actions={<AddAppDialog onSuccess={refetch} />}
				/>

				{/* Apps List */}
				{apps.length === 0 ? (
					<div className="rounded-lg border border-dashed border-border bg-muted/30 p-8 text-center">
						<FolderOpen className="mx-auto h-10 w-10 text-muted-foreground/50" />
						<p className="mt-3 text-sm text-muted-foreground">
							No apps configured yet.
						</p>
						<p className="text-xs text-muted-foreground/70">
							Add your first app to get started.
						</p>
					</div>
				) : (
					<div className="space-y-2">
						{apps.map((app) => {
							const isExpanded = expandedApp === app.id;
							const isBeingDeleted = isDeleting === app.id;

							return (
								<div
									key={app.id}
									className="rounded-lg border border-border bg-card overflow-hidden"
								>
									{/* App Header */}
									<div
										className="flex items-center gap-3 px-4 py-3 cursor-pointer hover:bg-muted/30 transition-colors"
										onClick={() => setExpandedApp(isExpanded ? null : app.id)}
									>
										<button
											className="shrink-0 text-muted-foreground"
											aria-label={isExpanded ? "Collapse" : "Expand"}
										>
											{isExpanded ? (
												<ChevronDown className="h-4 w-4" />
											) : (
												<ChevronRight className="h-4 w-4" />
											)}
										</button>

										<div className="flex items-center gap-2 min-w-0 flex-1">
											<Circle
												className={`h-2 w-2 shrink-0 ${
													app.isRunning
														? "fill-emerald-500 text-emerald-500"
														: "fill-muted text-muted"
												}`}
											/>
											<span className="font-medium text-sm truncate">
												{app.name}
											</span>
											{app.type && (
												<Badge variant="outline" className="text-xs shrink-0">
													{app.type}
												</Badge>
											)}
										</div>

										<div className="flex items-center gap-4 text-xs text-muted-foreground shrink-0">
											<div className="flex items-center gap-1">
												<span className="font-mono">{app.tasks.length}</span>
												<span>tasks</span>
											</div>
											<div className="flex items-center gap-1">
												<span className="font-mono">
													{app.variables.length + app.secrets.length}
												</span>
												<span>vars</span>
											</div>
											<Tooltip>
												<TooltipTrigger asChild>
													<span className="text-xs text-muted-foreground font-mono">
														:{app.port}
													</span>
												</TooltipTrigger>
												<TooltipContent>
													Stable port for this app
												</TooltipContent>
											</Tooltip>
										</div>

										<div className="flex items-center gap-1 shrink-0">
											<Button
												variant="ghost"
												size="icon"
												className="h-7 w-7"
												onClick={(e) => {
													e.stopPropagation();
													handleDelete(app.id);
												}}
												disabled={!token || isBeingDeleted}
											>
												{isBeingDeleted ? (
													<Loader2 className="h-3.5 w-3.5 animate-spin" />
												) : (
													<Trash2 className="h-3.5 w-3.5 text-muted-foreground hover:text-destructive" />
												)}
											</Button>
										</div>
									</div>

									{/* Expanded Content */}
									{isExpanded && (
										<div className="border-t border-border px-4 py-3 space-y-4 bg-muted/20">
											{/* App Details */}
											<div className="text-sm grid grid-cols-2 gap-2">
												<div className="flex items-center gap-2 text-muted-foreground text-xl">
													<FolderOpen className="h-3 w-3" />
													<span className="text-xs font-mono font-medium">
														{app.path}
													</span>
												</div>
												{app.domain && (
													<div className="text-xs text-muted-foreground">
														Domain:{" "}
														<span className="text-foreground font-mono font-medium">
															{app.domain}
														</span>
													</div>
												)}
												<div className="flex items-center gap-2 text-muted-foreground font-medium text-xl">
													{app.stablePort && (
														<span className="text-xs font-mono">
															{app.stablePort}
														</span>
													)}
												</div>

												{app.description && (
													<div className="text-xs text-muted-foreground col-span-2">
														{app.description}
													</div>
												)}
											</div>

											{/* Tasks Section */}
											<div>
												<div className="flex items-center justify-between mb-2">
													<div className="text-xs font-medium text-muted-foreground">
														Tasks ({app.tasks.length})
													</div>
												</div>
												{app.tasks.length === 0 ? (
													<p className="text-xs text-muted-foreground">
														No tasks discovered. Make sure the app has a
														package.json with scripts.
													</p>
												) : (
													<div className="space-y-1.5">
														{app.tasks.map((task) => {
															const isEditing =
																editingTask?.appId === app.id &&
																editingTask?.taskName === task.name;

															return (
																<div
																	key={task.name}
																	className="group flex items-center gap-2 px-3 py-2 rounded-md border border-border bg-background/70 hover:bg-background/10 cursor-pointer"
																>
																	<span className="text-xs font-medium min-w-32 text-primary/80 font-mono text-right pr-2">
																		{task.name}
																	</span>
																	{isEditing ? (
																		<div className="flex-1 flex items-center gap-2">
																			<Input
																				value={taskCommandOverride}
																				onChange={(e) =>
																					setTaskCommandOverride(e.target.value)
																				}
																				className="h-7 text-xs font-mono flex-1 font-medium"
																				autoFocus
																			/>
																			<Button
																				size="sm"
																				className="h-7 text-xs"
																				onClick={handleTaskSave}
																			>
																				Save
																			</Button>
																			<Button
																				size="sm"
																				variant="ghost"
																				className="h-7 text-xs"
																				onClick={handleTaskCancel}
																			>
																				Cancel
																			</Button>
																		</div>
																	) : (
																		<>
																			<span className="text-xs text-muted-foreground font-mono truncate flex-1 border-l pl-4">
																				{task.command}
																			</span>
																			<Button
																				variant="ghost"
																				size="icon"
																				className="h-6 w-6 opacity-0 group-hover:opacity-100 transition-opacity"
																				onClick={() =>
																					handleTaskEdit(
																						app.id,
																						task.name,
																						task.command,
																					)
																				}
																			>
																				<Pencil className="h-3 w-3" />
																			</Button>
																		</>
																	)}
																</div>
															);
														})}
													</div>
												)}
											</div>

											{/* Environment Variables Section */}
											<AppVariablesSection
												variables={app.variables}
												secrets={app.secrets}
												environmentOptions={environmentOptions}
												availableVariables={availableVariablesForAdd}
												onAddVariable={(
													envKey,
													variableId,
													environments,
													literalValue,
												) =>
													handleAddVariableToApp(
														app.id,
														envKey,
														variableId,
														environments,
														literalValue,
													)
												}
												onUpdateVariable={(
													oldEnvKey,
													newEnvKey,
													variableId,
													environments,
													literalValue,
												) =>
													handleUpdateVariableInApp(
														app.id,
														oldEnvKey,
														newEnvKey,
														variableId,
														environments,
														literalValue,
													)
												}
												onDeleteVariable={(envKey) =>
													handleDeleteVariableFromApp(app.id, envKey)
												}
												onUpdateEnvironments={(environments) =>
													handleUpdateEnvironmentsForApp(app.id, environments)
												}
												disabled={!token}
											/>
										</div>
									)}
								</div>
							);
						})}
					</div>
				)}
			</div>
		</TooltipProvider>
	);
}

export default AppsPanelAlt;
