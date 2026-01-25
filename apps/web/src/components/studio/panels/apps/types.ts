import type { VariableTypeName } from "../variables/constants";

export interface AppFormState {
	name: string;
	description: string;
	path: string;
	type: string;
	port?: number;
	domain?: string;
	commands: string[];
	variables: string[];
}

export const defaultFormState: AppFormState = {
	name: "",
	description: "",
	path: "",
	type: "bun",
	commands: [],
	variables: [],
};

/** Task with resolved command for display */
export interface TaskWithCommand {
	name: string;
	command: string;
	isOverridden: boolean;
}

/**
 * Variable with resolved details for display.
 * With simplified model, this shows key-value pairs from environments.
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
