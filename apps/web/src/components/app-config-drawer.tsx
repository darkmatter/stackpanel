import { Badge } from "@ui/badge";
import { Button } from "@ui/button";
import { Input } from "@ui/input";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@ui/tabs";
import { ToggleGroup, ToggleGroupItem } from "@ui/toggle-group";
import {
	ChevronDown,
	Key,
	Lock,
	Play,
	Trash2,
	Variable,
	X,
} from "lucide-react";
import type { AppConfigDrawerProps, Environment } from "./app-config-drawer";
import {
	AVAILABLE_TASKS,
	formatEnvironments,
	useAppConfigDrawer,
} from "./app-config-drawer";

export function AppConfigDrawer({
	app,
	open,
	onOpenChange,
}: AppConfigDrawerProps) {
	const {
		// Tab state
		activeTab,
		setActiveTab,
		selectedEnvironments,
		setSelectedEnvironments,

		// Task state
		taskConfigs,
		showTaskSuggestions,
		setShowTaskSuggestions,
		taskKeyInput,
		displayTasks,

		// Task handlers
		removeTask,
		updateTaskKey,
		updateTaskCommand,
		selectPredefinedTask,
		getDefaultScript,
		getFilteredTasks,

		// Variable state
		variableConfigs,
		showVariableSuggestions,
		setShowVariableSuggestions,
		variableNameInput,

		// Variable handlers
		removeVariable,
		getFilteredVariables,
		getSecretById,
		getFilteredVariablesForEnvironments,
		addVariableWithEnvironments,
		handleAddVariableInput,
	} = useAppConfigDrawer();

	if (!app) return null;

	return (
		<>
			{/* Backdrop */}
			<div
				className={`fixed inset-0 bg-black/50 transition-opacity z-40 ${
					open ? "opacity-100" : "opacity-0 pointer-events-none"
				}`}
				onClick={() => onOpenChange(false)}
			/>

			{/* Drawer */}
			<div
				className={`fixed right-0 top-0 h-full w-[600px] bg-background border-l border-border shadow-2xl transform transition-transform duration-300 z-50 flex flex-col ${
					open ? "translate-x-0" : "translate-x-full"
				}`}
			>
				{/* Header */}
				<div className="border-b border-border px-6 py-4 flex items-center justify-between">
					<div className="flex items-center gap-3">
						<div className="flex items-center gap-2">
							<h2 className="text-lg font-semibold">Configure App</h2>
							{app.badge && (
								<Badge
									variant="secondary"
									className="bg-yellow-500/20 text-yellow-600 dark:text-yellow-500"
								>
									{app.badge}
								</Badge>
							)}
						</div>
					</div>
					<Button
						variant="ghost"
						size="icon"
						onClick={() => onOpenChange(false)}
						className="h-8 w-8"
					>
						<X className="h-4 w-4" />
					</Button>
				</div>

				{/* App Info */}
				<div className="px-6 py-3 bg-muted/30 border-b border-border">
					<div className="text-sm">
						<div className="font-medium text-foreground mb-1">{app.name}</div>
						<div className="text-xs text-muted-foreground">{app.path}</div>
					</div>
				</div>

				{/* Tabs */}
				<Tabs
					value={activeTab}
					onValueChange={(v) => setActiveTab(v as "tasks" | "variables")}
					className="flex-1 flex flex-col"
				>
					<div className="px-6 pt-4">
						<TabsList className="w-full">
							<TabsTrigger value="tasks" className="flex-1">
								<Play className="h-4 w-4 mr-2" />
								Tasks
							</TabsTrigger>
							<TabsTrigger value="variables" className="flex-1">
								<Key className="h-4 w-4 mr-2" />
								Variables
							</TabsTrigger>
						</TabsList>
					</div>

					{/* Tasks Tab */}
					<TabsContent
						value="tasks"
						className="flex-1 overflow-auto px-6 py-4 space-y-4 mt-0"
					>
						<div className="space-y-3">
							<div className="flex items-center justify-between">
								<div>
									<h3 className="text-sm font-medium">Turbo Tasks</h3>
									<p className="text-xs text-muted-foreground mt-0.5">
										Define task scripts for this app (like package.json scripts)
									</p>
								</div>
							</div>

							<div className="space-y-2">
								{displayTasks.map((task, index) => {
									const isEmptyRow = index === taskConfigs.length;
									return (
										<div key={index} className="flex items-start gap-2 group">
											<div className="flex-1 grid grid-cols-[180px_1fr] gap-2">
												<div className="relative">
													<div className="relative">
														<Input
															value={taskKeyInput[index] ?? task.key}
															onChange={(e) =>
																updateTaskKey(index, e.target.value)
															}
															onFocus={() => setShowTaskSuggestions(index)}
															onBlur={() =>
																setTimeout(
																	() => setShowTaskSuggestions(null),
																	200,
																)
															}
															placeholder="Task name"
															className="h-9 text-sm font-mono pr-8"
														/>
														<Button
															variant="ghost"
															size="icon"
															className="absolute right-0 top-0 h-9 w-8 text-muted-foreground hover:text-foreground"
															onClick={() =>
																setShowTaskSuggestions(
																	showTaskSuggestions === index ? null : index,
																)
															}
														>
															<ChevronDown className="h-3.5 w-3.5" />
														</Button>
													</div>
													{showTaskSuggestions === index && (
														<div className="absolute top-full left-0 right-0 mt-1 bg-popover border border-border rounded-md shadow-lg z-10 max-h-48 overflow-auto">
															{getFilteredTasks(index).map((availableTask) => (
																<button
																	key={availableTask.name}
																	onClick={() =>
																		selectPredefinedTask(index, availableTask)
																	}
																	className="w-full px-3 py-2 text-left hover:bg-accent text-sm flex items-center justify-between"
																>
																	<div className="font-medium font-mono whitespace-pre">
																		{availableTask.name}
																	</div>
																	{availableTask.description && (
																		<div className="text-xs text-muted-foreground overflow-hidden whitespace-pre text-ellipsis pl-2">
																			{availableTask.description}
																		</div>
																	)}
																</button>
															))}
															{getFilteredTasks(index).length === 0 && (
																<div className="px-3 py-2 text-sm text-muted-foreground">
																	No matching tasks
																</div>
															)}
														</div>
													)}
												</div>
												<Input
													value={task.command}
													onChange={(e) =>
														updateTaskCommand(index, e.target.value)
													}
													placeholder={
														getDefaultScript(task.key) || "npm run ..."
													}
													className="h-9 text-sm font-mono"
												/>
											</div>
											{!isEmptyRow && (
												<Button
													variant="ghost"
													size="icon"
													onClick={() => removeTask(index)}
													className="h-9 w-9 opacity-0 group-hover:opacity-100 transition-opacity text-muted-foreground hover:text-destructive"
												>
													<Trash2 className="h-4 w-4" />
												</Button>
											)}
											{isEmptyRow && <div className="h-9 w-9" />}
										</div>
									);
								})}
							</div>
						</div>
					</TabsContent>

					{/* Variables Tab */}
					<TabsContent
						value="variables"
						className="flex-1 overflow-auto px-6 py-4 space-y-4 mt-0"
					>
						<div className="space-y-3">
							<div className="flex items-center justify-between">
								<div>
									<h3 className="text-sm font-medium">Environment Variables</h3>
									<p className="text-xs text-muted-foreground mt-0.5">
										Associate secrets and variables configured on the Secrets
										page
									</p>
								</div>
							</div>

							<div className="flex items-center gap-2 pb-2 border-b border-border">
								<span className="text-xs text-muted-foreground mr-1">
									Environments:
								</span>
								<ToggleGroup
									multiple
									value={selectedEnvironments}
									onValueChange={(value) => {
										if (value.length > 0) {
											setSelectedEnvironments(value as Environment[]);
										}
									}}
									className="gap-1"
								>
									<ToggleGroupItem value="development" className="h-7 text-xs">
										Development
									</ToggleGroupItem>
									<ToggleGroupItem value="staging" className="h-7 text-xs">
										Staging
									</ToggleGroupItem>
									<ToggleGroupItem value="production" className="h-7 text-xs">
										Production
									</ToggleGroupItem>
								</ToggleGroup>
								{selectedEnvironments.length > 1 && (
									<span className="text-xs text-muted-foreground">
										(showing common variables)
									</span>
								)}
							</div>

							<div className="space-y-2">
								{getFilteredVariablesForEnvironments().map((variable) => {
									const secret = getSecretById(variable.secretId);
									if (!secret) return null;

									return (
										<div
											key={variable.secretId}
											className="flex items-start gap-3 p-3 bg-muted/30 rounded-md border border-border group"
										>
											<div className="flex-shrink-0 mt-0.5">
												{secret.type === "secret" ? (
													<Lock className="h-4 w-4 text-orange-500" />
												) : (
													<Variable className="h-4 w-4 text-blue-500" />
												)}
											</div>
											<div className="flex-1 min-w-0">
												<div className="flex items-baseline gap-2 mb-0.5">
													<span className="font-mono text-sm font-medium">
														{secret.name}
													</span>
													{secret.type === "variable" && secret.value && (
														<>
															<span className="text-muted-foreground text-xs">
																=
															</span>
															<span className="text-xs text-muted-foreground font-mono truncate">
																{secret.value}
															</span>
														</>
													)}
												</div>
												<div className="text-xs text-muted-foreground">
													{formatEnvironments(variable.environments)}
												</div>
											</div>
											<Button
												variant="ghost"
												size="icon"
												onClick={() => {
													const index = variableConfigs.findIndex(
														(v) => v.secretId === variable.secretId,
													);
													if (index !== -1) removeVariable(index);
												}}
												className="h-8 w-8 opacity-0 group-hover:opacity-100 transition-opacity text-muted-foreground hover:text-destructive"
											>
												<Trash2 className="h-4 w-4" />
											</Button>
										</div>
									);
								})}

								<div className="flex items-start gap-2">
									<div className="flex-1 relative">
										<div className="relative">
											<Input
												value={variableNameInput[variableConfigs.length] ?? ""}
												onChange={(e) => handleAddVariableInput(e.target.value)}
												onFocus={() =>
													setShowVariableSuggestions(variableConfigs.length)
												}
												onBlur={() =>
													setTimeout(
														() => setShowVariableSuggestions(null),
														200,
													)
												}
												placeholder={
													selectedEnvironments.length > 1
														? `Add to ${selectedEnvironments.length} environments...`
														: "Add variable..."
												}
												className="h-9 text-sm font-mono pr-8"
											/>
											<Button
												variant="ghost"
												size="icon"
												className="absolute right-0 top-0 h-9 w-8 text-muted-foreground hover:text-foreground"
												onClick={() =>
													setShowVariableSuggestions(
														showVariableSuggestions === variableConfigs.length
															? null
															: variableConfigs.length,
													)
												}
											>
												<ChevronDown className="h-3.5 w-3.5" />
											</Button>
										</div>
										{showVariableSuggestions === variableConfigs.length && (
											<div className="absolute top-full left-0 right-0 mt-1 bg-popover border border-border rounded-md shadow-lg z-10 max-h-48 overflow-auto">
												{getFilteredVariables(variableConfigs.length).map(
													(availableSecret) => (
														<button
															key={availableSecret.id}
															onClick={() =>
																addVariableWithEnvironments(availableSecret.id)
															}
															className="w-full px-3 py-2 text-left hover:bg-accent text-sm flex flex-col gap-1"
														>
															<div className="flex items-center justify-between gap-2">
																<span className="font-medium font-mono">
																	{availableSecret.name}
																</span>
																<Badge
																	variant="outline"
																	className={`text-xs border-0 ${
																		availableSecret.type === "secret"
																			? "bg-orange-500/20 text-orange-600 dark:text-orange-400"
																			: "bg-blue-500/20 text-blue-600 dark:text-blue-400"
																	}`}
																>
																	{availableSecret.type}
																</Badge>
															</div>
															{availableSecret.type === "variable" &&
																availableSecret.value && (
																	<span className="text-xs text-muted-foreground font-mono truncate">
																		{availableSecret.value}
																	</span>
																)}
														</button>
													),
												)}
												{getFilteredVariables(variableConfigs.length).length ===
													0 && (
													<div className="px-3 py-2 text-sm text-muted-foreground">
														No available variables
													</div>
												)}
											</div>
										)}
									</div>
									<div className="h-9 w-9" />
								</div>
							</div>
						</div>
					</TabsContent>
				</Tabs>
			</div>
		</>
	);
}
