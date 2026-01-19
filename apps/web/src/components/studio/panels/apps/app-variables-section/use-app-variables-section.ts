/**
 * Hook for managing app variables section state.
 */
import { useMemo, useRef, useState } from "react";
import type {
	AppVariablesSectionProps,
	AvailableVariable,
	DisplayVariable,
	EditMode,
} from "./types";

export function useAppVariablesSection(
	props: Pick<
		AppVariablesSectionProps,
		| "variables"
		| "secrets"
		| "environmentOptions"
		| "availableVariables"
		| "onAddVariable"
		| "onUpdateVariable"
		| "onDeleteVariable"
		| "onUpdateEnvironments"
	>,
) {
	const {
		variables,
		secrets,
		environmentOptions,
		availableVariables = [],
		onAddVariable,
		onUpdateVariable,
		onDeleteVariable,
		onUpdateEnvironments,
	} = props;

	// Display state
	const [showEnvValues, setShowEnvValues] = useState(false);
	// Default to "dev" if it exists in the environment options
	const [environmentFilter, setEnvironmentFilter] = useState<string[]>(() => 
		environmentOptions.includes("dev") ? ["dev"] : []
	);

	// Environment editing state
	const [isEditingEnvironments, setIsEditingEnvironments] = useState(false);
	const [editedEnvironments, setEditedEnvironments] = useState<string[]>([]);
	const [newEnvName, setNewEnvName] = useState("");
	const newEnvInputRef = useRef<HTMLInputElement>(null);

	// Variable editing state
	const [editMode, setEditMode] = useState<EditMode | null>(null);
	const [editingEnvKey, setEditingEnvKey] = useState<string | null>(null);
	const [newEnvKey, setNewEnvKey] = useState("");
	const [selectedVariableId, setSelectedVariableId] = useState<string | null>(
		null,
	);
	const [isLiteralMode, setIsLiteralMode] = useState(false);
	const [literalValue, setLiteralValue] = useState("");
	const [variableSearchOpen, setVariableSearchOpen] = useState(false);
	const [variableSearch, setVariableSearch] = useState("");
	const envKeyInputRef = useRef<HTMLInputElement>(null);
	const literalInputRef = useRef<HTMLInputElement>(null);

	// Computed: filtered variables based on environment filter
	const filteredVariables = variables.filter((variable) => {
		if (environmentFilter.length === 0) return true;
		if (variable.environments.length === 0) return true;
		return variable.environments.some((env) => environmentFilter.includes(env));
	});

	const filteredSecrets = secrets.filter((secret) => {
		if (environmentFilter.length === 0) return true;
		if (secret.environments.length === 0) return true;
		return secret.environments.some((env) => environmentFilter.includes(env));
	});

	// Filter out already-linked variables from available options (except when editing that variable)
	const linkedVariableIds = useMemo(() => {
		const ids = new Set<string>();
		for (const v of variables) {
			// Don't exclude the currently editing variable
			if (editMode === "edit" && editingEnvKey === v.envKey) continue;
			ids.add(v.variableId);
		}
		for (const s of secrets) {
			if (editMode === "edit" && editingEnvKey === s.envKey) continue;
			ids.add(s.variableId);
		}
		return ids;
	}, [variables, secrets, editMode, editingEnvKey]);

	const unusedVariables = useMemo(() => {
		return availableVariables.filter((v) => !linkedVariableIds.has(v.id));
	}, [availableVariables, linkedVariableIds]);

	const filteredUnusedVariables = useMemo(() => {
		if (!variableSearch) return unusedVariables;
		const search = variableSearch.toLowerCase();
		return unusedVariables.filter(
			(v) =>
				v.key.toLowerCase().includes(search) ||
				v.id.toLowerCase().includes(search),
		);
	}, [unusedVariables, variableSearch]);

	const selectedVariable = useMemo(() => {
		if (!selectedVariableId) return null;
		return availableVariables.find((v) => v.id === selectedVariableId) ?? null;
	}, [availableVariables, selectedVariableId]);

	// Validation
	const canConfirm =
		newEnvKey.trim() &&
		((isLiteralMode && literalValue.trim()) ||
			(!isLiteralMode && selectedVariableId));

	const isEditing = editMode !== null;

	// Reset state helper
	const resetEditState = () => {
		setEditMode(null);
		setEditingEnvKey(null);
		setNewEnvKey("");
		setSelectedVariableId(null);
		setIsLiteralMode(false);
		setLiteralValue("");
		setVariableSearch("");
		setVariableSearchOpen(false);
	};

	// Environment editing handlers
	const handleStartEditingEnvironments = () => {
		setIsEditingEnvironments(true);
		// Ensure all environment names are strings (fixes "0" vs 0 type issues)
		setEditedEnvironments(environmentOptions.map((e) => String(e)));
		setNewEnvName("");
	};

	const handleCancelEditingEnvironments = () => {
		setIsEditingEnvironments(false);
		setEditedEnvironments([]);
		setNewEnvName("");
	};

	const handleSaveEnvironments = () => {
		if (onUpdateEnvironments && editedEnvironments.length > 0) {
			// Filter out any invalid environment names (empty strings, "0", numeric strings that look like indices)
			const validEnvs = editedEnvironments.filter(
				(e) => e && String(e).trim() && !/^\d+$/.test(String(e)),
			);
			// Only save if we have valid environments, otherwise keep the current ones
			if (validEnvs.length > 0) {
				onUpdateEnvironments(validEnvs);
			} else {
				onUpdateEnvironments(
					editedEnvironments.filter((e) => e && String(e).trim()),
				);
			}
		}
		setIsEditingEnvironments(false);
		setEditedEnvironments([]);
		setNewEnvName("");
	};

	const handleAddEnvironment = () => {
		const trimmed = newEnvName.trim().toLowerCase();
		// Don't allow numeric-only environment names (like "0", "1", etc.)
		if (
			trimmed &&
			!editedEnvironments.includes(trimmed) &&
			!/^\d+$/.test(trimmed)
		) {
			setEditedEnvironments([...editedEnvironments, trimmed]);
			setNewEnvName("");
			setTimeout(() => newEnvInputRef.current?.focus(), 0);
		}
	};

	const handleRemoveEnvironment = (env: string) => {
		// Don't allow removing the last environment
		if (editedEnvironments.length > 1) {
			// Use String() to ensure type-safe comparison (handles "0" vs 0 issues)
			const envStr = String(env);
			setEditedEnvironments(
				editedEnvironments.filter((e) => String(e) !== envStr),
			);
		}
	};

	const handleEnvKeyDown = (e: React.KeyboardEvent<HTMLInputElement>) => {
		if (e.key === "Enter") {
			e.preventDefault();
			handleAddEnvironment();
		} else if (e.key === "Escape") {
			handleCancelEditingEnvironments();
		}
	};

	// Variable editing handlers
	const handleStartAdding = () => {
		setEditMode("add");
		setEditingEnvKey(null);
		setNewEnvKey("");
		setSelectedVariableId(null);
		setIsLiteralMode(false);
		setLiteralValue("");
		setVariableSearch("");
		// Focus the input after render
		setTimeout(() => envKeyInputRef.current?.focus(), 0);
	};

	const handleStartEditing = (variable: DisplayVariable) => {
		setEditMode("edit");
		setEditingEnvKey(variable.envKey);
		setNewEnvKey(variable.envKey);

		// Check if it's a literal (no variableId) or linked variable
		if (variable.variableId) {
			setSelectedVariableId(variable.variableId);
			setIsLiteralMode(false);
			setLiteralValue("");
		} else {
			setSelectedVariableId(null);
			setIsLiteralMode(true);
			setLiteralValue(variable.value ?? "");
		}

		setVariableSearch("");
		// Focus the input after render
		setTimeout(() => envKeyInputRef.current?.focus(), 0);
	};

	const handleCancelEditing = () => {
		resetEditState();
	};

	const handleConfirm = () => {
		if (!newEnvKey.trim()) return;
		if (!isLiteralMode && !selectedVariableId) return;
		if (isLiteralMode && !literalValue.trim()) return;

		// Use selected environments, or all if none selected
		const envs =
			environmentFilter.length > 0 ? environmentFilter : environmentOptions;

		if (editMode === "add") {
			if (!onAddVariable) return;

			if (isLiteralMode) {
				onAddVariable(
					newEnvKey.trim().toUpperCase(),
					null,
					envs,
					literalValue.trim(),
				);
			} else {
				onAddVariable(
					newEnvKey.trim().toUpperCase(),
					selectedVariableId!,
					envs,
				);
			}
		} else if (editMode === "edit" && editingEnvKey) {
			if (!onUpdateVariable) return;

			if (isLiteralMode) {
				onUpdateVariable(
					editingEnvKey,
					newEnvKey.trim().toUpperCase(),
					null,
					envs,
					literalValue.trim(),
				);
			} else {
				onUpdateVariable(
					editingEnvKey,
					newEnvKey.trim().toUpperCase(),
					selectedVariableId!,
					envs,
				);
			}
		}

		resetEditState();
	};

	const handleDelete = () => {
		if (editMode !== "edit" || !editingEnvKey || !onDeleteVariable) return;
		onDeleteVariable(editingEnvKey);
		resetEditState();
	};

	const handleSelectVariable = (variableId: string) => {
		setSelectedVariableId(variableId);
		setIsLiteralMode(false);
		setLiteralValue("");
		setVariableSearchOpen(false);
		setVariableSearch("");

		// Auto-fill env key from variable key if empty (only when adding)
		if (!newEnvKey && editMode === "add") {
			const variable = availableVariables.find((v) => v.id === variableId);
			if (variable?.key) {
				setNewEnvKey(variable.key.toUpperCase());
			}
		}
	};

	const handleSelectLiteral = () => {
		setIsLiteralMode(true);
		setSelectedVariableId(null);
		setVariableSearchOpen(false);
		setVariableSearch("");
		// Focus the literal input after render
		setTimeout(() => literalInputRef.current?.focus(), 0);
	};

	return {
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
		selectedVariableId,
		isLiteralMode,
		literalValue,
		setLiteralValue,
		variableSearchOpen,
		setVariableSearchOpen,
		variableSearch,
		setVariableSearch,
		envKeyInputRef,
		literalInputRef,

		// Computed values
		filteredVariables,
		filteredSecrets,
		filteredUnusedVariables,
		unusedVariables,
		selectedVariable,
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
		handleSelectVariable,
		handleSelectLiteral,
	};
}
