/**
 * Hook for managing app config drawer state.
 */
import { useState } from "react";
import { AVAILABLE_SECRETS, AVAILABLE_TASKS } from "./constants";
import type {
	AvailableSecret,
	AvailableTask,
	Environment,
	TaskConfig,
	VariableConfig,
} from "./types";

export function useAppConfigDrawer() {
	// Tab state
	const [activeTab, setActiveTab] = useState<"tasks" | "variables">("tasks");
	const [selectedEnvironments, setSelectedEnvironments] = useState<
		Environment[]
	>(["development"]);

	// Task state
	const [taskConfigs, setTaskConfigs] = useState<TaskConfig[]>([
		{ key: "build", command: "npm run build" },
		{ key: "dev", command: "npm run dev -- --turbo" },
	]);
	const [showTaskSuggestions, setShowTaskSuggestions] = useState<number | null>(
		null,
	);
	const [taskKeyInput, setTaskKeyInput] = useState<{ [index: number]: string }>(
		{},
	);

	// Variable state
	const [variableConfigs, setVariableConfigs] = useState<VariableConfig[]>([
		{ secretId: "1", environments: ["development", "staging", "production"] },
		{ secretId: "2", environments: ["development", "staging"] },
		{ secretId: "3", environments: ["production"] },
	]);
	const [showVariableSuggestions, setShowVariableSuggestions] = useState<
		number | null
	>(null);
	const [variableNameInput, setVariableNameInput] = useState<{
		[index: number]: string;
	}>({});

	// Task handlers
	const removeTask = (index: number) => {
		setTaskConfigs(taskConfigs.filter((_, i) => i !== index));
	};

	const updateTaskKey = (index: number, key: string) => {
		if (index === taskConfigs.length) {
			setTaskConfigs([...taskConfigs, { key, command: "" }]);
		} else {
			const updated = [...taskConfigs];
			updated[index] = { ...updated[index], key };
			setTaskConfigs(updated);
		}
		setTaskKeyInput({ ...taskKeyInput, [index]: key });
	};

	const updateTaskCommand = (index: number, command: string) => {
		if (index === taskConfigs.length) {
			setTaskConfigs([...taskConfigs, { key: "", command }]);
		} else {
			const updated = [...taskConfigs];
			updated[index] = { ...updated[index], command };
			setTaskConfigs(updated);
		}
	};

	const selectPredefinedTask = (index: number, task: AvailableTask) => {
		if (index === taskConfigs.length) {
			setTaskConfigs([
				...taskConfigs,
				{ key: task.name, command: task.defaultScript },
			]);
		} else {
			const updated = [...taskConfigs];
			updated[index] = { key: task.name, command: task.defaultScript };
			setTaskConfigs(updated);
		}
		setTaskKeyInput({ ...taskKeyInput, [index]: task.name });
		setShowTaskSuggestions(null);
	};

	const getDefaultScript = (key: string): string => {
		const task = AVAILABLE_TASKS.find((t) => t.name === key);
		return task?.defaultScript || "";
	};

	const getFilteredTasks = (index: number): AvailableTask[] => {
		const input = taskKeyInput[index] || taskConfigs[index]?.key || "";
		if (!input) return AVAILABLE_TASKS;
		return AVAILABLE_TASKS.filter((t) =>
			t.name.toLowerCase().includes(input.toLowerCase()),
		);
	};

	// Variable handlers
	const removeVariable = (index: number) => {
		setVariableConfigs(variableConfigs.filter((_, i) => i !== index));
	};

	const updateVariableName = (index: number, name: string) => {
		const secret = AVAILABLE_SECRETS.find((s) => s.name === name);
		if (index === variableConfigs.length) {
			if (secret) {
				setVariableConfigs([
					...variableConfigs,
					{ secretId: secret.id, environments: [] },
				]);
			}
		} else {
			if (secret) {
				const updated = [...variableConfigs];
				updated[index] = { ...updated[index], secretId: secret.id };
				setVariableConfigs(updated);
			}
		}
		setVariableNameInput({ ...variableNameInput, [index]: name });
	};

	const selectPredefinedVariable = (index: number, secret: AvailableSecret) => {
		if (index === variableConfigs.length) {
			setVariableConfigs([
				...variableConfigs,
				{ secretId: secret.id, environments: [] },
			]);
		} else {
			const updated = [...variableConfigs];
			updated[index] = { ...updated[index], secretId: secret.id };
			setVariableConfigs(updated);
		}
		setVariableNameInput({ ...variableNameInput, [index]: secret.name });
		setShowVariableSuggestions(null);
	};

	const getFilteredVariables = (index: number): AvailableSecret[] => {
		const input = variableNameInput[index] || "";
		const usedSecretIds = variableConfigs
			.filter((_, i) => i !== index)
			.map((v) => v.secretId);
		const availableToAdd = AVAILABLE_SECRETS.filter(
			(s) => !usedSecretIds.includes(s.id),
		);

		if (!input) return availableToAdd;
		return availableToAdd.filter((s) =>
			s.name.toLowerCase().includes(input.toLowerCase()),
		);
	};

	const getSecretById = (id: string): AvailableSecret | undefined => {
		return AVAILABLE_SECRETS.find((s) => s.id === id);
	};

	const getFilteredVariablesForEnvironments = (): VariableConfig[] => {
		if (selectedEnvironments.length === 0) return [];
		return variableConfigs.filter((config) =>
			selectedEnvironments.every((env) => config.environments.includes(env)),
		);
	};

	// Add new variable with selected environments
	const addVariableWithEnvironments = (secretId: string) => {
		setVariableConfigs([
			...variableConfigs,
			{ secretId, environments: selectedEnvironments },
		]);
		setVariableNameInput({});
		setShowVariableSuggestions(null);
	};

	// Update variable name input handler for add form
	const handleAddVariableInput = (name: string) => {
		const secret = AVAILABLE_SECRETS.find((s) => s.name === name);
		if (secret) {
			addVariableWithEnvironments(secret.id);
		} else {
			setVariableNameInput({
				...variableNameInput,
				[variableConfigs.length]: name,
			});
		}
	};

	// Computed values
	const displayTasks = [...taskConfigs, { key: "", command: "" }];
	const displayVariables = [
		...variableConfigs,
		{ secretId: "", environments: [] as Environment[] },
	];

	return {
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
		displayVariables,

		// Variable handlers
		removeVariable,
		updateVariableName,
		selectPredefinedVariable,
		getFilteredVariables,
		getSecretById,
		getFilteredVariablesForEnvironments,
		addVariableWithEnvironments,
		handleAddVariableInput,
	};
}
