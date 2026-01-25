"use client";

import { Input } from "@ui/input";
import { ToggleGroup, ToggleGroupItem } from "@ui/toggle-group";
import { Check, Eye, EyeOff, Pencil, Plus, X } from "lucide-react";
import type { AppVariablesSectionProps } from "./app-variables-section/types";
import { EditInterface, VariableBadge } from "./app-variables-section/components";
import { useAppVariablesSection } from "./app-variables-section/use-app-variables-section";

/**
 * Component to display and manage the variables section for an app.
 * Shows variables/secrets with environment filtering and show/hide values toggle.
 * 
 * Updated for simplified schema where variables are key-value pairs.
 */
export function AppVariablesSection({
	variables,
	secrets,
	environmentOptions,
	availableVariables,
	onAddVariable,
	onUpdateVariable,
	onDeleteVariable,
	onUpdateEnvironments,
	disabled,
}: AppVariablesSectionProps) {
	const {
		// Display state
		showEnvValues,
		setShowEnvValues,
		environmentFilter,
		setEnvironmentFilter,

		// Environment editing state
		isEditingEnvironments,
		editedEnvironments,
		newEnvName,
		setNewEnvName,
		newEnvInputRef,

		// Variable editing state
		editMode,
		editingEnvKey,
		newEnvKey,
		setNewEnvKey,
		editValue,
		setEditValue,
		envKeyInputRef,
		literalInputRef,

		// Computed values
		filteredVariables,
		filteredSecrets,
		canConfirm,
		isEditing,

		// Environment editing handlers
		handleStartEditingEnvironments,
		handleCancelEditingEnvironments,
		handleSaveEnvironments,
		handleAddEnvironment,
		handleRemoveEnvironment,
		handleEnvKeyDown,

		// Variable editing handlers
		handleStartAdding,
		handleStartEditing,
		handleCancelEditing,
		handleConfirm,
		handleDelete,
	} = useAppVariablesSection({
		variables,
		secrets,
		environmentOptions,
		onAddVariable,
		onUpdateVariable,
		onDeleteVariable,
		onUpdateEnvironments,
	});

	// Render the edit/add interface
	const renderEditInterface = () => (
		<EditInterface
			newEnvKey={newEnvKey}
			setNewEnvKey={setNewEnvKey}
			editValue={editValue}
			setEditValue={setEditValue}
			canConfirm={canConfirm}
			editMode={editMode}
			envKeyInputRef={envKeyInputRef}
			literalInputRef={literalInputRef}
			availableVariables={availableVariables}
			onConfirm={handleConfirm}
			onCancel={handleCancelEditing}
			onDelete={onDeleteVariable ? handleDelete : undefined}
		/>
	);

	return (
		<div className="space-y-3">
			<div className="text-xs font-medium text-primary">Variables</div>
			<div className="flex items-center justify-between">
				<div className="flex items-center gap-3">
					{isEditingEnvironments ? (
						<div className="flex items-center gap-1 rounded-md border border-primary/20 bg-background p-1">
							{editedEnvironments.map((env) => (
								<div
									key={env}
									className="flex items-center gap-1 px-2 py-0.5 rounded bg-muted text-xs"
								>
									<span>{env}</span>
									<button
										type="button"
										onClick={() => handleRemoveEnvironment(env)}
										disabled={editedEnvironments.length <= 1}
										className="text-muted-foreground hover:text-destructive disabled:opacity-30 disabled:cursor-not-allowed"
										title={
											editedEnvironments.length <= 1
												? "At least one environment required"
												: "Remove environment"
										}
									>
										<X className="h-3 w-3" />
									</button>
								</div>
							))}
							<Input
								ref={newEnvInputRef}
								value={newEnvName}
								onChange={(e) => setNewEnvName(e.target.value.toLowerCase())}
								onKeyDown={handleEnvKeyDown}
								placeholder="new env..."
								className="h-6 w-20 border-0 bg-transparent text-xs focus-visible:ring-0 focus-visible:ring-offset-0 placeholder:text-muted-foreground/50"
							/>
							<button
								type="button"
								onClick={handleAddEnvironment}
								disabled={
									!newEnvName.trim() ||
									editedEnvironments.includes(newEnvName.trim().toLowerCase())
								}
								className="h-6 w-6 flex items-center justify-center text-primary hover:bg-primary/10 rounded disabled:opacity-30 disabled:cursor-not-allowed"
								title="Add environment"
							>
								<Plus className="h-3 w-3" />
							</button>
							<div className="w-px h-4 bg-border mx-1" />
							<button
								type="button"
								onClick={handleSaveEnvironments}
								className="h-6 w-6 flex items-center justify-center text-emerald-500 hover:bg-emerald-500/10 rounded"
								title="Save environments"
							>
								<Check className="h-3 w-3" />
							</button>
							<button
								type="button"
								onClick={handleCancelEditingEnvironments}
								className="h-6 w-6 flex items-center justify-center text-muted-foreground hover:text-destructive hover:bg-destructive/10 rounded"
								title="Cancel"
							>
								<X className="h-3 w-3" />
							</button>
						</div>
					) : (
						<>
							<ToggleGroup
								type="multiple"
								value={environmentFilter}
								onValueChange={setEnvironmentFilter}
								className="gap-0"
								variant="secondary"
							>
								{environmentOptions.map((env) => (
									<ToggleGroupItem
										key={env}
										value={env}
										variant="secondary"
										size="xs"
									>
										{env}
									</ToggleGroupItem>
								))}
							</ToggleGroup>
							{onUpdateEnvironments && !disabled && (
								<button
									type="button"
									onClick={handleStartEditingEnvironments}
									className="p-1 text-muted-foreground hover:text-foreground transition-colors"
									title="Edit environments"
								>
									<Pencil className="h-3 w-3" />
								</button>
							)}
						</>
					)}
				</div>
				<div className="flex items-center gap-2">
					<button
						onClick={() => setShowEnvValues(!showEnvValues)}
						className="flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground transition-colors"
					>
						{showEnvValues ? (
							<>
								<EyeOff className="h-3 w-3" />
								<span>Hide</span>
							</>
						) : (
							<>
								<Eye className="h-3 w-3" />
								<span>Show</span>
							</>
						)}
					</button>
				</div>
			</div>
			<div className="flex flex-wrap gap-2">
				{/* Render filtered variables */}
				{filteredVariables.map((variable) => (
					<VariableBadge
						key={`var-${variable.envKey}`}
						variable={variable}
						isSecret={false}
						isCurrentlyEditing={
							editMode === "edit" && editingEnvKey === variable.envKey
						}
						showEnvValues={showEnvValues}
						disabled={disabled}
						isEditing={isEditing}
						onStartEditing={handleStartEditing}
						renderEditInterface={renderEditInterface}
					/>
				))}

				{/* Render filtered secrets */}
				{filteredSecrets.map((secret) => (
					<VariableBadge
						key={`secret-${secret.envKey}`}
						variable={secret}
						isSecret={true}
						isCurrentlyEditing={
							editMode === "edit" && editingEnvKey === secret.envKey
						}
						showEnvValues={showEnvValues}
						disabled={disabled}
						isEditing={isEditing}
						onStartEditing={handleStartEditing}
						renderEditInterface={renderEditInterface}
					/>
				))}

				{/* Add interface (when adding new) */}
				{editMode === "add" && renderEditInterface()}

				{/* Add button (when not editing) */}
				{!isEditing && (
					<button
						onClick={handleStartAdding}
						className="flex items-center gap-1.5 px-3 py-1.5 rounded-md border border-dashed border-border hover:border-primary hover:bg-primary/5 transition-colors text-xs text-muted-foreground hover:text-foreground"
						disabled={disabled || !onAddVariable}
					>
						<Plus className="h-3 w-3" />
						<span>Add variable</span>
					</button>
				)}
			</div>
		</div>
	);
}
