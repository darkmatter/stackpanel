"use client";

import { Badge } from "@ui/badge";
import { Button } from "@ui/button";
import { Popover, PopoverContent, PopoverTrigger } from "@ui/popover";
import { ChevronDown, ChevronRight, Plus, Variable, X } from "lucide-react";
import { useMemo, useState } from "react";
import type { AppVariable, Variable as WorkspaceVariable } from "@/lib/types";
import { AddVariableDialog } from "../variables/add-variable-dialog";

interface AppVariablesProps {
	/** Variables linked to this app (map of variable name to AppVariable) */
	variables: Record<string, AppVariable> | undefined;
	/** All workspace variables available for linking */
	allVariables?: Record<string, WorkspaceVariable>;
	/** Callback when variables are updated */
	onUpdate?: (variables: Record<string, AppVariable>) => void;
	/** Callback when a new variable is added (to trigger refetch) */
	onVariableAdded?: () => void;
	/** Whether editing is disabled */
	disabled?: boolean;
}

/**
 * Component to display and manage linked variables for an app
 */
export function AppVariables({
	variables,
	allVariables,
	onUpdate,
	onVariableAdded,
	disabled,
}: AppVariablesProps) {
	const [isOpen, setIsOpen] = useState(false);
	const [linkPopoverOpen, setLinkPopoverOpen] = useState(false);

	const variableEntries = Object.entries(variables ?? {});
	const canEdit = !disabled && onUpdate && allVariables;

	// Get list of variables that can be linked (not already linked)
	const availableVariables = useMemo(() => {
		if (!allVariables) return [];
		const linkedIds = new Set(Object.keys(variables ?? {}));
		return Object.entries(allVariables)
			.filter(([id]) => !linkedIds.has(id))
			.map(([id, v]) => ({ id, key: v.key || id, type: v.type }));
	}, [allVariables, variables]);

	const handleLinkVariable = (variableId: string) => {
		if (!onUpdate) return;
		const newVariables = {
			...variables,
			[variableId]: {
				variable_id: variableId,
				environments: [],
			},
		};
		onUpdate(newVariables);
		setLinkPopoverOpen(false);
	};

	const handleUnlinkVariable = (variableId: string) => {
		if (!onUpdate || !variables) return;
		const newVariables = { ...variables };
		delete newVariables[variableId];
		onUpdate(newVariables);
	};

	// Show empty state with add button if editable
	if (variableEntries.length === 0) {
		return (
			<div className="flex items-center gap-2">
				<span className="text-muted-foreground text-xs">
					No variables linked
				</span>
				{canEdit && (
					<>
						{availableVariables.length > 0 && (
							<LinkVariablePopover
								availableVariables={availableVariables}
								onLink={handleLinkVariable}
								open={linkPopoverOpen}
								onOpenChange={setLinkPopoverOpen}
							/>
						)}
						{onVariableAdded && (
							<AddVariableDialog onSuccess={onVariableAdded} />
						)}
					</>
				)}
			</div>
		);
	}

	return (
		<div>
			<div className="flex items-center gap-1">
				<Button
					variant="ghost"
					size="sm"
					className="h-auto gap-1 p-1 text-xs"
					onClick={() => setIsOpen(!isOpen)}
				>
					{isOpen ? (
						<ChevronDown className="h-3 w-3" />
					) : (
						<ChevronRight className="h-3 w-3" />
					)}
					<Variable className="h-3 w-3 text-accent" />
					<span>
						{variableEntries.length} variable
						{variableEntries.length !== 1 ? "s" : ""}
					</span>
				</Button>
				{canEdit && (
					<>
						{availableVariables.length > 0 && (
							<LinkVariablePopover
								availableVariables={availableVariables}
								onLink={handleLinkVariable}
								open={linkPopoverOpen}
								onOpenChange={setLinkPopoverOpen}
							/>
						)}
						{onVariableAdded && (
							<AddVariableDialog onSuccess={onVariableAdded} />
						)}
					</>
				)}
			</div>
			{isOpen && (
				<div className="mt-2 space-y-1">
					{variableEntries.map(([varName, variable]) => {
						const workspaceVar = allVariables?.[varName];
						return (
							<div
								key={varName}
								className="group flex items-center gap-2 rounded-md bg-secondary/50 px-2 py-1 text-xs"
							>
								<Variable className="h-3 w-3 text-muted-foreground" />
								<code className="font-mono">
									{workspaceVar?.key || varName}
								</code>
								{variable.variable_id && variable.variable_id !== varName && (
									<span className="text-muted-foreground">
										→ {variable.variable_id}
									</span>
								)}
								{variable.environments?.length ? (
									<span className="ml-auto flex items-center gap-1">
										{variable.environments.map((env) => (
											<Badge
												key={env}
												variant="outline"
												className="border-border"
											>
												{env}
											</Badge>
										))}
									</span>
								) : (
									<Badge variant="outline" className="ml-auto border-border">
										all
									</Badge>
								)}
								{canEdit && (
									<Button
										variant="ghost"
										size="icon"
										className="h-5 w-5 opacity-0 group-hover:opacity-100 transition-opacity"
										onClick={() => handleUnlinkVariable(varName)}
									>
										<X className="h-3 w-3 text-muted-foreground hover:text-destructive" />
									</Button>
								)}
							</div>
						);
					})}
				</div>
			)}
		</div>
	);
}

interface LinkVariablePopoverProps {
	availableVariables: { id: string; key: string; type?: number }[];
	onLink: (variableId: string) => void;
	open: boolean;
	onOpenChange: (open: boolean) => void;
}

function LinkVariablePopover({
	availableVariables,
	onLink,
	open,
	onOpenChange,
}: LinkVariablePopoverProps) {
	return (
		<Popover open={open} onOpenChange={onOpenChange}>
			<PopoverTrigger
				render={(props) => (
					<button
						{...props}
						type="button"
						className="flex items-center gap-1 px-2 py-0.5 rounded-md border border-dashed border-border bg-background text-xs hover:border-accent/50 hover:bg-accent/5 transition-colors"
					>
						<Plus className="h-3 w-3 text-accent" />
						<span>Link</span>
					</button>
				)}
			/>
			<PopoverContent className="w-56 p-2" align="start">
				<div className="space-y-1">
					<p className="text-xs font-medium text-muted-foreground px-2 pb-1">
						Link variable
					</p>
					<div className="max-h-48 overflow-y-auto space-y-0.5">
						{availableVariables.map((v) => (
							<button
								key={v.id}
								type="button"
								className="w-full flex items-center gap-2 px-2 py-1.5 rounded-md text-xs hover:bg-secondary/50 transition-colors text-left"
								onClick={() => onLink(v.id)}
							>
								<Variable className="h-3 w-3 text-muted-foreground flex-shrink-0" />
								<code className="font-mono truncate">{v.key}</code>
							</button>
						))}
					</div>
				</div>
			</PopoverContent>
		</Popover>
	);
}
