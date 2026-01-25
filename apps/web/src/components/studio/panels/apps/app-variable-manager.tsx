// @ts-nocheck - Legacy component, not actively used with new simplified schema
"use client";

// Note: This component uses the old schema with AppVariableType.
// The new schema uses simple key-value pairs in environments.env
// This file is kept for reference but should be migrated or removed.

// Legacy type - no longer in proto schema
enum AppVariableType {
  UNSPECIFIED = 0,
  VARIABLE = 1,
  LITERAL = 2,
}
import { Button } from "@ui/button";
import { Input } from "@ui/input";
import { Label } from "@ui/label";
import { ScrollArea } from "@ui/scroll-area";
import {
	Select,
	SelectContent,
	SelectItem,
	SelectTrigger,
	SelectValue,
} from "@ui/select";
import { Textarea } from "@ui/textarea";
import { Trash2 } from "lucide-react";
import { useCallback, useEffect, useMemo, useState } from "react";
import type {
	AppEnvironment,
	AppVariable,
	Variable as WorkspaceVariable,
} from "@/lib/types";
import { MultiSelectWithAdd } from "../shared/multi-select-with-add";

// =============================================================================
// Types
// =============================================================================

interface VariableRow {
	/** Unique key for React rendering */
	rowId: string;
	/** Variable ID from workspace (empty for new rows) */
	variableId: string;
	/** Variable name/key for display */
	variableName: string;
	/** Optional custom environment key override */
	customKey: string;
	/** Variable value */
	value: string;
	/** Environments this variable is scoped to for this app */
	environments: string[];
	/** Whether this row has unsaved changes */
	isDirty: boolean;
}

interface AppVariableManagerProps {
	/** Current app variable associations */
	appVariables: Record<string, AppVariable>;
	/** All workspace variables available for linking */
	workspaceVariables: Record<string, WorkspaceVariable>;
	/** Available environments */
	environments: string[];
	/** Currently selected environment filter */
	selectedEnvironment: string;
	/** Callback when app variables change */
	onChange: (variables: Record<string, AppVariable>) => void;
	/** Callback when environment filter changes */
	onEnvironmentChange: (environment: string) => void;
}

// =============================================================================
// Component
// =============================================================================

export function AppVariableManager({
	appVariables,
	workspaceVariables,
	environments,
	selectedEnvironment,
	onChange,
	onEnvironmentChange,
}: AppVariableManagerProps) {
	const [rows, setRows] = useState<VariableRow[]>([]);

	// Get available environments (include "all" option)
	const environmentOptions = useMemo(
		() => ["all", ...environments],
		[environments],
	);

	/** Helper to extract environment names from AppEnvironment map */
	const getEnvironmentNames = (
		environments: Record<string, AppEnvironment> | undefined,
	): string[] => {
		if (!environments) return [];
		return Object.keys(environments);
	};

	/** Helper to convert environment names to AppEnvironment map for API */
	const toEnvironmentsMap = (
		envNames: string[],
	): Record<string, AppEnvironment> => {
		const result: Record<string, AppEnvironment> = {};
		for (const name of envNames) {
			result[name] = { name, variables: {} };
		}
		return result;
	};

	// Filter app variables based on selected environment
	const filteredAppVariables = useMemo(() => {
		if (selectedEnvironment === "all") {
			return appVariables;
		}

		const result: Record<string, AppVariable> = {};
		for (const [varId, appVar] of Object.entries(appVariables)) {
			const envNames = getEnvironmentNames(appVar.environments);
			// If variable has no environments, it's in all environments
			if (envNames.length === 0) {
				result[varId] = appVar;
				continue;
			}

			// Check if variable is in selected environment
			if (envNames.includes(selectedEnvironment)) {
				result[varId] = appVar;
			}
		}
		return result;
	}, [appVariables, selectedEnvironment]);

	// Get list of workspace variables not yet linked
	const availableVariables = useMemo(() => {
		const linkedIds = new Set(Object.keys(appVariables));
		return Object.entries(workspaceVariables)
			.filter(([id]) => !linkedIds.has(id))
			.map(([id, variable]) => ({
				id,
				name: variable.key || id,
			}));
	}, [workspaceVariables, appVariables]);

	// Initialize rows from filtered app variables
	useEffect(() => {
		const variableRows: VariableRow[] = Object.entries(
			filteredAppVariables,
		).map(([varId, appVar]) => {
			const workspaceVar = workspaceVariables[varId];
			return {
				rowId: varId,
				variableId: varId,
				variableName: workspaceVar?.key || varId,
				customKey: "", // TODO: Get from appVar if we store it
				value: workspaceVar?.value || "",
				environments: getEnvironmentNames(appVar.environments),
				isDirty: false,
			};
		});

		// Add empty row at the end if there are available variables
		if (availableVariables.length > 0) {
			variableRows.push({
				rowId: `new-${Date.now()}`,
				variableId: "",
				variableName: "",
				customKey: "",
				value: "",
				environments: [],
				isDirty: false,
			});
		}

		setRows(variableRows);
	}, [filteredAppVariables, workspaceVariables, availableVariables]);

	const updateRow = useCallback(
		(rowId: string, updates: Partial<VariableRow>) => {
			setRows((prev) => {
				const newRows = prev.map((row) => {
					if (row.rowId !== rowId) return row;
					return { ...row, ...updates, isDirty: true };
				});

				// Auto-save when a complete row is modified
				const updatedRow = newRows.find((r) => r.rowId === rowId);
				if (updatedRow?.variableId && updatedRow.isDirty) {
					// Create updated app variables map
					const newAppVariables = { ...appVariables };
					newAppVariables[updatedRow.variableId] = {
						key: updatedRow.variableId,
						type: AppVariableType.VARIABLE,
						variable_id: updatedRow.variableId,
						environments: toEnvironmentsMap(updatedRow.environments),
					};
					onChange(newAppVariables);

					// Mark row as saved
					return newRows.map((r) =>
						r.rowId === rowId ? { ...r, isDirty: false } : r,
					);
				}

				return newRows;
			});
		},
		[appVariables, onChange],
	);

	const handleVariableSelect = useCallback(
		(rowId: string, variableId: string) => {
			const workspaceVar = workspaceVariables[variableId];
			if (!workspaceVar) return;

			// Update the row
			const envNames =
				selectedEnvironment === "all" ? [] : [selectedEnvironment];
			const updatedRow = {
				variableId,
				variableName: workspaceVar.key || variableId,
				value: workspaceVar.value || "",
				environments: envNames,
			};

			setRows((prev) => {
				const newRows = prev.map((row) =>
					row.rowId === rowId ? { ...row, ...updatedRow } : row,
				);

				// Add the variable to app variables
				const newAppVariables = { ...appVariables };
				newAppVariables[variableId] = {
					key: variableId,
					type: AppVariableType.VARIABLE,
					variable_id: variableId,
					environments: toEnvironmentsMap(envNames),
				};
				onChange(newAppVariables);

				// Add new empty row if this was the last one
				if (rowId.startsWith("new-")) {
					newRows.push({
						rowId: `new-${Date.now()}`,
						variableId: "",
						variableName: "",
						customKey: "",
						value: "",
						environments: [],
						isDirty: false,
					});
				}

				return newRows;
			});
		},
		[workspaceVariables, appVariables, selectedEnvironment, onChange],
	);

	const handleDelete = useCallback(
		(rowId: string) => {
			const row = rows.find((r) => r.rowId === rowId);
			if (!row?.variableId) return;

			// Remove from app variables
			const newAppVariables = { ...appVariables };
			delete newAppVariables[row.variableId];
			onChange(newAppVariables);

			// Remove row
			setRows((prev) => prev.filter((r) => r.rowId !== rowId));
		},
		[rows, appVariables, onChange],
	);

	return (
		<div className="space-y-4">
			{/* Environment Filter */}
			<div className="space-y-2">
				<Label>Filter by Environment</Label>
				<div className="flex items-center gap-2">
					<Select
						value={selectedEnvironment}
						onValueChange={onEnvironmentChange}
					>
						<SelectTrigger className="w-48">
							<SelectValue />
						</SelectTrigger>
						<SelectContent>
							{environmentOptions.map((env) => (
								<SelectItem key={env} value={env}>
									<span className="capitalize">{env}</span>
								</SelectItem>
							))}
						</SelectContent>
					</Select>
				</div>
				<p className="text-xs text-muted-foreground">
					{selectedEnvironment === "all"
						? "Showing all linked variables"
						: `Showing variables available in ${selectedEnvironment}`}
				</p>
			</div>

			{/* Variable Table */}
			<div className="border rounded-lg">
				<ScrollArea className="h-[400px]">
					<div className="divide-y divide-border">
						{/* Header */}
						<div className="grid grid-cols-[2fr,2fr,3fr,2fr,40px] gap-2 p-2 bg-muted/50 text-xs font-medium text-muted-foreground sticky top-0 z-10">
							<div>Variable</div>
							<div>Default Environment Key</div>
							<div>Value</div>
							<div>Environments</div>
							<div />
						</div>

						{/* Rows */}
						{rows.map((row) => (
							<div
								key={row.rowId}
								className={`grid grid-cols-[2fr,2fr,3fr,2fr,40px] gap-2 p-2 items-start hover:bg-muted/30 ${
									row.isDirty ? "bg-blue-500/5" : ""
								}`}
							>
								{/* Variable Selector */}
								<div className="pt-1">
									{row.variableId ? (
										<code className="text-xs font-mono">
											{row.variableName}
										</code>
									) : (
										<Select
											value={row.variableId}
											onValueChange={(val) =>
												handleVariableSelect(row.rowId, val)
											}
										>
											<SelectTrigger className="h-8 text-xs bg-background">
												<SelectValue placeholder="Select variable..." />
											</SelectTrigger>
											<SelectContent>
												{availableVariables.map((v) => (
													<SelectItem key={v.id} value={v.id}>
														<code className="font-mono text-xs">{v.name}</code>
													</SelectItem>
												))}
											</SelectContent>
										</Select>
									)}
								</div>

								{/* Custom Key (optional) */}
								<div>
									<Input
										value={row.customKey}
										onChange={(e) =>
											updateRow(row.rowId, { customKey: e.target.value })
										}
										placeholder="Optional override..."
										className="h-8 text-xs font-mono bg-background"
										disabled={!row.variableId}
									/>
								</div>

								{/* Value (multiline, monospace) */}
								<div>
									<Textarea
										value={row.value}
										onChange={(e) =>
											updateRow(row.rowId, { value: e.target.value })
										}
										placeholder="Variable value..."
										className="min-h-20 text-xs font-mono bg-background resize-none"
										disabled={!row.variableId}
									/>
								</div>

								{/* Environments (multi-select with add) */}
								<div className="pt-1">
									<MultiSelectWithAdd
										options={environments}
										selectedValues={row.environments}
										onSelectionChange={(envs) =>
											updateRow(row.rowId, { environments: envs })
										}
										placeholder="All environments"
										disabled={!row.variableId}
									/>
								</div>

								{/* Actions */}
								<div className="flex items-center justify-center pt-1">
									{row.variableId ? (
										<Button
											variant="ghost"
											size="icon"
											className="h-8 w-8"
											onClick={() => handleDelete(row.rowId)}
										>
											<Trash2 className="h-3 w-3 text-muted-foreground hover:text-destructive" />
										</Button>
									) : null}
								</div>
							</div>
						))}
					</div>
				</ScrollArea>
			</div>

			<p className="text-xs text-muted-foreground">
				Select a variable from the dropdown to link it to this app. You can
				optionally override the environment key and customize the value.
			</p>
		</div>
	);
}
