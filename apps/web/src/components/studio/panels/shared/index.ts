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
	NixPanel,
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

// Panel renderers
export {
	AppConfigFormRenderer,
	AppsGridPanelRenderer,
	PanelRenderer,
	StatusPanelRenderer,
} from "./panel-renderers";
