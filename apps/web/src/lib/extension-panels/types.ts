/**
 * Extension Panels Type Definitions
 *
 * Types for the extension panels system. These mirror the proto schema
 * definitions and are used by the component registry to render panels.
 */

// =============================================================================
// Field Types (from proto FieldType enum)
// =============================================================================

export type FieldType =
  | "FIELD_TYPE_UNSPECIFIED"
  | "FIELD_TYPE_STRING"
  | "FIELD_TYPE_NUMBER"
  | "FIELD_TYPE_BOOLEAN"
  | "FIELD_TYPE_SELECT"
  | "FIELD_TYPE_MULTISELECT"
  | "FIELD_TYPE_APP_FILTER"
  | "FIELD_TYPE_COLUMNS";

// =============================================================================
// Panel Types (from proto PanelType enum)
// =============================================================================

export type PanelType =
  | "PANEL_TYPE_UNSPECIFIED"
  | "PANEL_TYPE_APPS_GRID"
  | "PANEL_TYPE_STATUS"
  | "PANEL_TYPE_FORM";

// =============================================================================
// Panel Field (from proto PanelField message)
// =============================================================================

export interface PanelField {
  /** Field name (maps to component prop) */
  name: string;
  /** Field type */
  type: FieldType;
  /** Field value (JSON-encoded for complex types) */
  value: string;
  /** Options for select fields */
  options?: string[];
}

// =============================================================================
// Extension Panel (from proto ExtensionPanel message)
// =============================================================================

export interface ExtensionPanel {
  /** Unique panel identifier */
  id: string;
  /** Display title */
  title: string;
  /** Panel description */
  description?: string;
  /** Panel type (determines which component to render) */
  type: PanelType;
  /** Display order (lower = first) */
  order: number;
  /** Panel configuration fields */
  fields: PanelField[];
}

// =============================================================================
// Extension App Data (from proto ExtensionAppData message)
// =============================================================================

export interface ExtensionAppData {
  /** Whether extension is enabled for this app */
  enabled: boolean;
  /** Extension config for this app (string key-value pairs) */
  config: Record<string, string>;
}

// =============================================================================
// Extension (from proto Extension message)
// =============================================================================

export interface Extension {
  /** Display name of the extension */
  name: string;
  /** Whether this extension is enabled */
  enabled: boolean;
  /** Load order priority (lower = earlier) */
  priority?: number;
  /** Tags for categorizing/filtering extensions */
  tags?: string[];
  /** UI panels provided by this extension */
  panels: ExtensionPanel[];
  /** Per-app extension data (app name -> extension data) */
  apps: Record<string, ExtensionAppData>;
}

// =============================================================================
// App Data (base app info from nix eval)
// =============================================================================

export interface AppData {
  /** App port */
  port: number;
  /** App domain (e.g., "myapp.localhost") */
  domain?: string | null;
  /** App URL (e.g., "http://myapp.localhost") */
  url?: string | null;
  /** Whether TLS is enabled */
  tls: boolean;
}

// =============================================================================
// Component Props
// =============================================================================

/** Base props passed to all panel components */
export interface BasePanelProps {
  /** The extension this panel belongs to */
  extension: Extension;
  /** All apps from nix eval config.apps */
  allApps: Record<string, AppData>;
}

/** Props for AppsGridPanel component */
export interface AppsGridProps extends BasePanelProps {
  /** Filter expression for apps (e.g., "go.enable") */
  filter?: string;
  /** Columns to display */
  columns?: string[];
}

/** Metric item for status panels */
export interface StatusMetric {
  /** Metric label */
  label: string;
  /** Metric value */
  value: string | number;
  /** Status indicator */
  status?: "ok" | "warning" | "error";
}

/** Props for StatusPanel component */
export interface StatusPanelProps extends BasePanelProps {
  /** Metrics to display */
  metrics: StatusMetric[];
}

/** Props for ConfigFormPanel component */
export interface ConfigFormProps extends BasePanelProps {
  /** JSON Schema for the form */
  schema?: Record<string, unknown>;
  /** Current form values */
  values?: Record<string, unknown>;
  /** Save handler */
  onSave?: (values: Record<string, unknown>) => Promise<void>;
}

// =============================================================================
// Nix Config Response (from agent nix-config endpoint)
// =============================================================================

export interface NixConfigResponse {
  /** Apps from stackpanel.apps */
  apps: Record<string, AppData>;
  /** Extensions from stackpanel.extensions */
  extensions: Record<string, Extension>;
  /** Project name */
  projectName?: string;
  /** Base port */
  basePort?: number;
}
