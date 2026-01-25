/**
 * Extension Panel Registry
 *
 * Maps panel types to React components and handles field parsing.
 * This is the central registry for rendering extension panels.
 */

import type { ReactElement } from "react";
import { AppsGridPanel } from "./panels/apps-grid";
import { StatusPanel } from "./panels/status";
import type {
	AppData,
	Extension,
	ExtensionPanel,
	FieldType as _FieldType,
	PanelField,
	PanelType,
	StatusMetric,
} from "./types";

// =============================================================================
// Component Registry
// =============================================================================

// biome-ignore lint/suspicious/noExplicitAny: Component props vary by panel type
type PanelComponent = React.ComponentType<any>;

const componentRegistry: Partial<Record<PanelType, PanelComponent>> = {
	PANEL_TYPE_APPS_GRID: AppsGridPanel,
	PANEL_TYPE_STATUS: StatusPanel,
	// PANEL_TYPE_FORM: ConfigFormPanel, // TODO: Add form panel
};

// =============================================================================
// Field Parsing
// =============================================================================

/**
 * Parse panel fields into typed props for the component.
 *
 * Handles JSON decoding for complex types and type coercion for primitives.
 */
export function parseFields(fields: PanelField[]): Record<string, unknown> {
	const props: Record<string, unknown> = {};

	for (const field of fields) {
		try {
			switch (field.type) {
				case "FIELD_TYPE_STRING":
					props[field.name] = field.value;
					break;

				case "FIELD_TYPE_NUMBER":
					props[field.name] = Number(field.value);
					break;

				case "FIELD_TYPE_BOOLEAN":
					props[field.name] = field.value === "true";
					break;

				case "FIELD_TYPE_SELECT":
					props[field.name] = field.value;
					break;

				case "FIELD_TYPE_MULTISELECT":
				case "FIELD_TYPE_COLUMNS":
				case "FIELD_TYPE_APP_FILTER":
					// These are JSON-encoded arrays or objects
					props[field.name] = field.value ? JSON.parse(field.value) : undefined;
					break;

				default:
					// For unspecified types, try to parse as JSON, fall back to string
					try {
						props[field.name] = JSON.parse(field.value);
					} catch {
						props[field.name] = field.value;
					}
			}
		} catch (error) {
			console.warn(
				`Failed to parse field "${field.name}" with type "${field.type}":`,
				error,
			);
			props[field.name] = field.value;
		}
	}

	return props;
}

/**
 * Parse metrics field for status panels.
 *
 * Metrics can be:
 * - A JSON string containing an array of metrics
 * - Already an array (from parseFields)
 */
export function parseMetrics(value: unknown): StatusMetric[] {
	if (!value) return [];

	if (typeof value === "string") {
		try {
			return JSON.parse(value) as StatusMetric[];
		} catch {
			return [];
		}
	}

	if (Array.isArray(value)) {
		return value as StatusMetric[];
	}

	return [];
}

// =============================================================================
// Panel Rendering
// =============================================================================

/**
 * Render a single extension panel.
 *
 * Looks up the component in the registry, parses fields into props,
 * and returns the rendered component.
 */
export function renderPanel(
	panel: ExtensionPanel,
	extension: Extension,
	allApps: Record<string, AppData>,
): ReactElement | null {
	const Component = componentRegistry[panel.type];

	if (!Component) {
		console.warn(`No component registered for panel type: ${panel.type}`);
		return null;
	}

	const fieldProps = parseFields(panel.fields);

	// Special handling for metrics in status panels
	if (panel.type === "PANEL_TYPE_STATUS" && fieldProps.metrics) {
		fieldProps.metrics = parseMetrics(fieldProps.metrics);
	}

	return (
		<Component
			key={panel.id}
			extension={extension}
			allApps={allApps}
			{...fieldProps}
		/>
	);
}

/**
 * Render all panels for an extension, sorted by order.
 */
export function renderExtensionPanels(
	extension: Extension,
	allApps: Record<string, AppData>,
): ReactElement[] {
	const sortedPanels = [...extension.panels].sort((a, b) => a.order - b.order);

	return sortedPanels
		.map((panel) => renderPanel(panel, extension, allApps))
		.filter((el): el is ReactElement => el !== null);
}

// =============================================================================
// Registry Utilities
// =============================================================================

/**
 * Check if a panel type is supported.
 */
export function isPanelTypeSupported(type: PanelType): boolean {
	return type in componentRegistry;
}

/**
 * Get all registered panel types.
 */
export function getRegisteredPanelTypes(): PanelType[] {
	return Object.keys(componentRegistry) as PanelType[];
}
