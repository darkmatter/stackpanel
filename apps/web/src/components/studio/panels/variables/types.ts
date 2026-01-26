import type { Variable } from "@stackpanel/proto";
import type { VariableTypeName } from "./constants";

/**
 * Extended variable form state for UI editing.
 * Note: Variable now only has id and value fields.
 */
export interface VariableFormState {
	/** Variable ID (e.g., "/dev/DATABASE_URL") */
	id: string;
	/** Variable value (literal or vals reference) */
	value: string;
	/** UI-only: derived type name for display */
	typeName?: VariableTypeName;
}

/**
 * Create default form state for a new variable.
 * Default keygroup is "dev" for secrets.
 */
export const defaultFormState: VariableFormState = {
	id: "/dev/",
	value: "",
};

/**
 * Convert a Variable to form state.
 */
export function variableToFormState(variable: Variable, fallbackId = ""): VariableFormState {
	return {
		id: variable.id ?? fallbackId,
		value: variable.value,
	};
}

/**
 * Convert form state to a Variable.
 */
export function formStateToVariable(formState: VariableFormState): Variable {
	return {
		id: formState.id,
		value: formState.value,
	};
}
