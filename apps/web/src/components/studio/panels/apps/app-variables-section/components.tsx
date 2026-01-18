/**
 * Sub-components for the app variables section.
 */
"use client";

import { VariableType } from "@stackpanel/proto";
import { Input } from "@ui/input";
import { Popover, PopoverContent, PopoverTrigger } from "@ui/popover";
import {
	Calculator,
	Check,
	ChevronDown,
	Lock,
	Trash2,
	Type,
	VariableIcon,
	X,
} from "lucide-react";
import type { RefObject } from "react";
import type { AvailableVariable, DisplayVariable, EditMode } from "./types";

/**
 * Props for the EditInterface component.
 */
interface EditInterfaceProps {
	// State
	newEnvKey: string;
	setNewEnvKey: (value: string) => void;
	isLiteralMode: boolean;
	literalValue: string;
	setLiteralValue: (value: string) => void;
	variableSearchOpen: boolean;
	setVariableSearchOpen: (open: boolean) => void;
	variableSearch: string;
	setVariableSearch: (value: string) => void;
	selectedVariable: AvailableVariable | null;
	filteredUnusedVariables: AvailableVariable[];
	unusedVariables: AvailableVariable[];
	canConfirm: boolean;
	editMode: EditMode | null;

	// Refs
	envKeyInputRef: RefObject<HTMLInputElement | null>;
	literalInputRef: RefObject<HTMLInputElement | null>;

	// Handlers
	onSelectVariable: (variableId: string) => void;
	onSelectLiteral: () => void;
	onConfirm: () => void;
	onCancel: () => void;
	onDelete?: () => void;
}

/**
 * Edit/add interface for variables.
 */
export function EditInterface({
	newEnvKey,
	setNewEnvKey,
	isLiteralMode,
	literalValue,
	setLiteralValue,
	variableSearchOpen,
	setVariableSearchOpen,
	variableSearch,
	setVariableSearch,
	selectedVariable,
	filteredUnusedVariables,
	unusedVariables,
	canConfirm,
	editMode,
	envKeyInputRef,
	literalInputRef,
	onSelectVariable,
	onSelectLiteral,
	onConfirm,
	onCancel,
	onDelete,
}: EditInterfaceProps) {
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

			{/* Variable Selector or Literal Input */}
			{isLiteralMode ? (
				<Input
					ref={literalInputRef}
					value={literalValue}
					onChange={(e) => setLiteralValue(e.target.value)}
					placeholder="Enter value..."
					className="h-8 w-40 border-0 rounded-none bg-transparent text-xs font-mono focus-visible:ring-0 focus-visible:ring-offset-0 placeholder:text-muted-foreground/50"
				/>
			) : (
				<Popover open={variableSearchOpen} onOpenChange={setVariableSearchOpen}>
					<PopoverTrigger asChild>
						<button
							type="button"
							className="flex items-center gap-1.5 h-8 px-2 min-w-32 hover:bg-muted/50 transition-colors"
						>
							{selectedVariable ? (
								<>
									{selectedVariable.type === VariableType.SECRET ? (
										<Lock className="h-3 w-3 text-orange-500 shrink-0" />
									) : (
										<VariableIcon className="h-3 w-3 text-blue-500 shrink-0" />
									)}
									<span className="truncate">{selectedVariable.key}</span>
								</>
							) : (
								<span className="text-muted-foreground">
									Select variable...
								</span>
							)}
							<ChevronDown className="h-3 w-3 text-muted-foreground ml-auto shrink-0" />
						</button>
					</PopoverTrigger>
					<PopoverContent className="w-56 p-0" align="start">
						<div className="p-2 border-b border-border">
							<Input
								value={variableSearch}
								onChange={(e) => setVariableSearch(e.target.value)}
								placeholder="Search variables..."
								className="h-7 text-xs"
							/>
						</div>
						<div className="max-h-48 overflow-y-auto p-1">
							{/* Add Literal option */}
							<button
								type="button"
								onClick={onSelectLiteral}
								className="w-full flex items-center gap-2 px-2 py-1.5 rounded text-xs hover:bg-muted transition-colors text-left mb-1 pb-2"
							>
								<Type className="h-3 w-3 text-emerald-500 shrink-0" />
								<span className="font-medium">Add Literal</span>
								<span className="text-muted-foreground ml-auto text-[10px]">
									raw value
								</span>
							</button>
							<button
								type="button"
								onClick={() => {
									window.open("/studio/variables?action=new", "_blank");
								}}
								className="w-full flex items-center gap-2 px-2 py-1.5 rounded text-xs hover:bg-muted transition-colors text-left border-b border-border/50 mb-1 pb-2"
							>
								<VariableIcon className="h-3 w-3 text-blue-500 shrink-0" />
								<span className="font-medium">Add Variable</span>
								<span className="text-muted-foreground ml-auto text-[10px]">
									Opens in new window
								</span>
							</button>
							{filteredUnusedVariables.length === 0 ? (
								<p className="text-xs text-muted-foreground px-2 py-3 text-center">
									{unusedVariables.length === 0
										? "No variables available"
										: "No matching variables"}
								</p>
							) : (
								filteredUnusedVariables.map((variable) => (
									<button
										key={variable.id}
										type="button"
										onClick={() => onSelectVariable(variable.id)}
										className="w-full flex text-gray-300 text-shadow-accent-foreground items-center gap-2 px-2 py-1.5 rounded font-mono text-xs hover:bg-muted transition-colors text-left"
									>
										{variable.type === VariableType.SECRET ? (
											<Lock className="h-3 w-3 text-orange-500 shrink-0" />
										) : (
											<VariableIcon className="h-3 w-3 text-blue-500 shrink-0" />
										)}
										<span className="truncate font-medium">{variable.key}</span>
									</button>
								))
							)}
						</div>
					</PopoverContent>
				</Popover>
			)}

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
	const isComputed = variable.type === VariableType.VALS;

	// If this variable is being edited, show the edit interface instead
	if (isCurrentlyEditing) {
		return <>{renderEditInterface()}</>;
	}

	return (
		<button
			key={`${variable.envKey}-${variable.variableId}`}
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
