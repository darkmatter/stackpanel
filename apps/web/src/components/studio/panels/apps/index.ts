export { AddAppDialog } from "./add-app-dialog";
export {
	type AppForm,
	AppFormFields,
	type AppFormValues,
	appFormSchema,
	parsePortValue,
} from "./app-form-fields";
export { AppTasks } from "./app-tasks";
export { AppVariablesSection } from "./app-variables-section";
export {
	APP_TYPES,
	type AppType,
	getTypeColor,
	getTypeLabel,
} from "./constants";
// Hooks
export { useAppMutations } from "./hooks";
export {
	type AppFormState,
	type DisplayVariable,
	defaultFormState,
	type TaskWithCommand,
} from "./types";

// Utils
export {
	type AppVariableMapping,
	buildEnvironmentsMap,
	computeStablePort,
	flattenEnvironmentVariables,
	getEnvironmentNames,
	toEnvironmentsMap,
} from "./utils";
