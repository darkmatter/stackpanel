export { AddAppDialog } from "./add-app-dialog";
export {
  type AppForm,
  AppFormFields,
  type AppFormValues,
  appFormSchema,
  parsePortValue,
} from "./app-form-fields";
export { AppTasks } from "./app-tasks";
export { AppVariableManager } from "./app-variable-manager";
export { AppVariables } from "./app-variables";
export { AppVariablesSection } from "./app-variables-section";
export {
  APP_TYPES,
  type AppType,
  getTypeColor,
  getTypeLabel,
} from "./constants";
export {
  type AppFormState,
  defaultFormState,
  type DisplayVariable,
  type TaskWithCommand,
} from "./types";

// Hooks
export { useAppMutations } from "./hooks";

// Utils
export {
  type AppVariableMapping,
  buildEnvironmentsMap,
  computeStablePort,
  flattenEnvironmentVariables,
  getEnvironmentNames,
  toEnvironmentsMap,
} from "./utils";
