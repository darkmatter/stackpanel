/**
 * Extension Panels Module
 *
 * Provides the infrastructure for rendering extension-defined UI panels.
 */

// Panel Components
export { AppsGridPanel } from "./panels/apps-grid";
export { StatusPanel } from "./panels/status";
// Registry
export {
	getRegisteredPanelTypes,
	isPanelTypeSupported,
	parseFields,
	parseMetrics,
	renderExtensionPanels,
	renderPanel,
} from "./registry";
// Types
export type {
	AppData,
	AppsGridProps,
	BasePanelProps,
	ConfigFormProps,
	Extension,
	ExtensionAppData,
	ExtensionPanel,
	FieldType,
	NixConfigResponse,
	PanelField,
	PanelType,
	StatusMetric,
	StatusPanelProps,
} from "./types";
