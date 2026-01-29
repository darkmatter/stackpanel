// Entity form (pre-existing)
export {
	createEnumOptions,
	EntityForm,
	type EntityForm as EntityFormInstance,
	type EntityFormProps,
	type FieldConfig,
	type FieldOption,
	type FieldType,
	toKebabCase,
	toScreamingSnakeCase,
} from "./entity-form";
export { GuideDialog } from "./guide-dialog";
export { guides, HelpButton } from "./help-button";
export { MultiSelect } from "./multi-select";
export { MultiSelectWithAdd } from "./multi-select-with-add";
export { PanelHeader, type PanelHeaderProps } from "./panel-header";

// Panel types
export type {
	AppConfigField,
	AppModulePanel,
	MetricItem,
	ModuleGroup,
	ModuleMeta,
	NixFieldOption,
	NixPanel,
	NixPanelColumn,
	NixPanelField,
} from "./panel-types";

// Module utilities
export { formatModuleName } from "./module-utils";
export {
	getModuleIconById,
	getModuleIconByName,
	MODULE_ICONS,
} from "./module-icons";

// Field renderers
export { FieldRenderer, type FieldRendererProps } from "./field-renderer";
export { FieldDisplay, type FieldDisplayProps } from "./field-display";

// Editable field components
export {
	EditableField,
	EditableFieldGroup,
	FieldInput,
	useFieldEditor,
	type EditableFieldConfig,
	type EditableFieldItem,
	type EditableFieldProps,
	type EditableFieldGroupProps,
	type FieldInputProps,
	type FieldSaveTarget,
	type UseFieldEditorOptions,
	type FieldEditorState,
} from "./editable-field";

// Panel renderers
export {
	AppConfigFormRenderer,
	AppsGridPanelRenderer,
	FormPanelRenderer,
	PanelRenderer,
	StatusPanelRenderer,
	TablePanelRenderer,
} from "./panel-renderers";
