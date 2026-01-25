/**
 * Sub-components for the app variables section.
 * 
 * Updated for simplified schema where variables are key-value pairs.
 */
"use client";

import { Input } from "@ui/input";
import {
	Select,
	SelectContent,
	SelectItem,
	SelectTrigger,
	SelectValue,
} from "@ui/select";
import {
	Calculator,
	Check,
	Lock,
	Trash2,
	VariableIcon,
	X,
} from "lucide-react";
import type { RefObject } from "react";
import type { AvailableVariable, DisplayVariable, EditMode } from "./types";
import { isSopsReference, isValsReference } from "../utils";

/**
 * Props for the EditInterface component.
 * Simplified for key-value editing with optional variable selector.
 */
interface EditInterfaceProps {
	// State
	newEnvKey: string;
	setNewEnvKey: (value: string) => void;
	editValue: string;
	setEditValue: (value: string) => void;
	canConfirm: boolean;
	editMode: EditMode | null;

	// Refs
	envKeyInputRef: RefObject<HTMLInputElement | null>;
	literalInputRef: RefObject<HTMLInputElement | null>;

	// Optional: available variables for linking
	availableVariables?: AvailableVariable[];

	// Handlers
	onConfirm: () => void;
	onCancel: () => void;
	onDelete?: () => void;
}

/**
 * Build a vals reference for a variable ID.
 * E.g., "/dev/DATABASE_URL" → "ref+sops://.stackpanel/secrets/dev.yaml#/DATABASE_URL"
 */
function buildValsReference(variableId: string): string {
	// Parse the variable ID: /<env>/<NAME>
	const parts = variableId.split("/").filter(Boolean);
	if (parts.length >= 2) {
		const env = parts[0]; // e.g., "dev", "prod"
		const name = parts.slice(1).join("/"); // e.g., "DATABASE_URL"
		return `ref+sops://.stackpanel/secrets/${env}.yaml#/${name}`;
	}
	// Fallback for non-standard IDs
	return `ref+sops://.stackpanel/secrets/dev.yaml#${variableId}`;
}

/**
 * Extract env key suggestion from variable ID.
 * E.g., "/dev/DATABASE_URL" → "DATABASE_URL"
 */
function suggestEnvKey(variableId: string): string {
	const parts = variableId.split("/").filter(Boolean);
	if (parts.length >= 2) {
		return parts[parts.length - 1]; // Last part is the var name
	}
	return variableId.replace(/[^A-Z0-9_]/gi, "_").toUpperCase();
}

/**
 * Edit/add interface for variables.
 * Includes a dropdown to select from available workspace variables.
 */
export function EditInterface({
	newEnvKey,
	setNewEnvKey,
	editValue,
	setEditValue,
	canConfirm,
	editMode,
	envKeyInputRef,
	literalInputRef,
	availableVariables,
	onConfirm,
	onCancel,
	onDelete,
}: EditInterfaceProps) {
	const handleSelectVariable = (variableId: string) => {
		const variable = availableVariables?.find((v) => v.id === variableId);
		if (!variable) return;
		
		// Set the value to the vals reference
		setEditValue(buildValsReference(variable.id));
		// Suggest an env key based on the variable name
		if (!newEnvKey) {
			setNewEnvKey(suggestEnvKey(variable.id));
		}
	};

	return (
		<div className="flex items-center gap-0.5 rounded-md border border-primary/10 bg-background text-xs overflow-hidden">
			{/* Env Key Input */}
			<Input
				ref={envKeyInputRef}
				value={newEnvKey}
				onChange={(e) => setNewEnvKey(e.target.value.toUpperCase())}
				placeholder="ENV_KEY"
				className="h-8 w-28 border-0 rounded-none bg-transparent text-xs font-mono focus-visible:ring-0 focus-visible:ring-offset-0 placeholder:text-muted-foreground/50"
			/>

			{/* Subtle divider */}
			<div className="w-px h-5 bg-border/50" />

			{/* Variable Selector Dropdown (when available variables exist) */}
			{availableVariables && availableVariables.length > 0 && (
				<>
					<Select onValueChange={handleSelectVariable}>
						<SelectTrigger className="h-8 w-32 border-0 rounded-none bg-transparent text-xs focus:ring-0">
							<SelectValue placeholder="Link variable..." />
						</SelectTrigger>
						<SelectContent>
							{availableVariables.map((variable) => (
								<SelectItem key={variable.id} value={variable.id}>
									<div className="flex items-center gap-2">
										{variable.typeName === "secret" ? (
											<Lock className="h-3 w-3 text-orange-500" />
										) : variable.typeName === "computed" ? (
											<Calculator className="h-3 w-3 text-purple-500" />
										) : (
											<VariableIcon className="h-3 w-3 text-blue-500" />
										)}
										<span className="font-mono text-xs">{variable.name}</span>
									</div>
								</SelectItem>
							))}
						</SelectContent>
					</Select>
					<div className="w-px h-5 bg-border/50" />
				</>
			)}

			{/* Value Input */}
			<Input
				ref={literalInputRef}
				value={editValue}
				onChange={(e) => setEditValue(e.target.value)}
				placeholder="value or ref+sops://..."
				className="h-8 w-48 border-0 rounded-none bg-transparent text-xs font-mono focus-visible:ring-0 focus-visible:ring-offset-0 placeholder:text-muted-foreground/50"
			/>

			{/* Action buttons */}
			<div className="flex items-center border-l border-border/50">
				{editMode === "edit" && onDelete && (
					<button
						type="button"
						onClick={onDelete}
						className="h-8 w-8 flex items-center justify-center hover:bg-destructive/10 text-muted-foreground hover:text-destructive transition-colors"
						title="Delete variable"
					>
						<Trash2 className="h-3.5 w-3.5" />
					</button>
				)}
				<button
					type="button"
					onClick={onConfirm}
					disabled={!canConfirm}
					className="h-8 w-8 flex items-center justify-center hover:bg-emerald-500/10 text-emerald-500 disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
					title={editMode === "edit" ? "Save changes" : "Add variable"}
				>
					<Check className="h-3.5 w-3.5" />
				</button>
				<button
					type="button"
					onClick={onCancel}
					className="h-8 w-8 flex items-center justify-center hover:bg-destructive/10 text-muted-foreground hover:text-destructive transition-colors"
					title="Cancel"
				>
					<X className="h-3.5 w-3.5" />
				</button>
			</div>
		</div>
	);
}

/**
 * Props for the VariableBadge component.
 */
interface VariableBadgeProps {
	variable: DisplayVariable;
	isSecret: boolean;
	isCurrentlyEditing: boolean;
	showEnvValues: boolean;
	disabled?: boolean;
	isEditing: boolean;
	onStartEditing: (variable: DisplayVariable) => void;
	renderEditInterface: () => React.ReactNode;
}

/**
 * Clickable badge for a variable.
 */
export function VariableBadge({
	variable,
	isSecret,
	isCurrentlyEditing,
	showEnvValues,
	disabled,
	isEditing,
	onStartEditing,
	renderEditInterface,
}: VariableBadgeProps) {
	// Derive type from value
	const isComputed = isValsReference(variable.value) && !isSopsReference(variable.value);

	// If this variable is being edited, show the edit interface instead
	if (isCurrentlyEditing) {
		return <>{renderEditInterface()}</>;
	}

	return (
		<button
			key={variable.envKey}
			type="button"
			onClick={() => !disabled && onStartEditing(variable)}
			disabled={disabled || isEditing}
			className="flex items-center gap-2 px-3 py-1.5 rounded-md border border-border bg-background text-xs hover:border-primary/50 hover:bg-muted/30 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
		>
			{isSecret ? (
				<Lock className="h-3 w-3 text-orange-500" />
			) : isComputed ? (
				<Calculator className="h-3 w-3 text-purple-500" />
			) : (
				<VariableIcon className="h-3 w-3 text-blue-500" />
			)}
			<span className="font-medium">{variable.envKey}</span>
			{!isSecret && variable.value && (
				<>
					<span className="text-muted-foreground">=</span>
					<span className="text-muted-foreground font-mono truncate max-w-50">
						{showEnvValues ? variable.value : "••••••"}
					</span>
				</>
			)}
			{isSecret && <span className="text-muted-foreground">••••••</span>}
		</button>
	);
}
