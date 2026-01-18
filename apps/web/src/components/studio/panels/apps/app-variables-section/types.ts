/**
 * Type definitions for the app variables section.
 */
import type { VariableType } from "@stackpanel/proto";

/**
 * A variable displayed in the UI, including its mapping to an env key.
 */
export interface DisplayVariable {
	envKey: string;
	variableId: string;
	variableKey: string;
	type: VariableType | null;
	description: string;
	value?: string;
	environments: string[];
	isSecret: boolean;
}

/**
 * An available workspace variable that can be linked to an app.
 */
export interface AvailableVariable {
	id: string;
	key: string;
	type: VariableType | null;
}

/**
 * Props for the AppVariablesSection component.
 */
export interface AppVariablesSectionProps {
	/** Regular variables for this app */
	variables: DisplayVariable[];
	/** Secret variables for this app */
	secrets: DisplayVariable[];
	/** Available environment options */
	environmentOptions: string[];
	/** All available workspace variables that can be linked */
	availableVariables?: AvailableVariable[];
	/** Callback when a new variable mapping is added (variableId is null for literals) */
	onAddVariable?: (
		envKey: string,
		variableId: string | null,
		environments: string[],
		literalValue?: string,
	) => void;
	/** Callback when a variable mapping is updated */
	onUpdateVariable?: (
		oldEnvKey: string,
		newEnvKey: string,
		variableId: string | null,
		environments: string[],
		literalValue?: string,
	) => void;
	/** Callback when a variable mapping is deleted */
	onDeleteVariable?: (envKey: string) => void;
	/** Callback when environments list is updated */
	onUpdateEnvironments?: (environments: string[]) => void;
	/** Whether actions are disabled */
	disabled?: boolean;
}

/**
 * Current edit mode for the variable editor.
 */
export type EditMode = "add" | "edit";

/**
 * State shape for the app variables section hook.
 */
export interface AppVariablesSectionState {
	// Display state
	showEnvValues: boolean;
	environmentFilter: string[];

	// Environment editing state
	isEditingEnvironments: boolean;
	editedEnvironments: string[];
	newEnvName: string;

	// Variable editing state
	editMode: EditMode | null;
	editingEnvKey: string | null;
	newEnvKey: string;
	selectedVariableId: string | null;
	isLiteralMode: boolean;
	literalValue: string;
	variableSearchOpen: boolean;
	variableSearch: string;
}
