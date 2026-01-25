/**
 * Type definitions for the app variables section.
 * 
 * With the simplified model, environment variables are now simple
 * key-value pairs (env: { [key: string]: string }).
 */
import type { VariableTypeName } from "../../variables/constants";

/**
 * A variable displayed in the UI, including its mapping to an env key.
 */
export interface DisplayVariable {
	/** Environment variable name (e.g., "DATABASE_URL") */
	envKey: string;
	/** The value - literal string or vals reference */
	value: string;
	/** Environment names this variable is set in */
	environments: string[];
	/** UI-derived: whether this is a secret (based on value pattern) */
	isSecret: boolean;
	/** UI-derived: type name for display */
	typeName: VariableTypeName;
}

/**
 * An available workspace variable that can be linked to an app.
 */
export interface AvailableVariable {
	/** Variable ID (e.g., "/dev/DATABASE_URL") */
	id: string;
	/** Derived variable name from ID */
	name: string;
	/** UI-derived: type name for display */
	typeName: VariableTypeName;
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
	/** Callback when a new variable is added */
	onAddVariable?: (
		envKey: string,
		value: string,
		environments: string[],
	) => void;
	/** Callback when a variable is updated */
	onUpdateVariable?: (
		oldEnvKey: string,
		newEnvKey: string,
		value: string,
		environments: string[],
	) => void;
	/** Callback when a variable is deleted */
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
	/** The value being edited (literal or vals ref) */
	editValue: string;
	/** Whether we're linking to a workspace variable */
	isLinkingVariable: boolean;
	variableSearchOpen: boolean;
	variableSearch: string;
}
