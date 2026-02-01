// =============================================================================
// Shared panel types used by panels-panel, app-expanded-content, and renderers.
// =============================================================================

/** Column definition for TABLE panels */
export interface NixPanelColumn {
  key: string;
  label: string;
}

/** Option for SELECT fields - can be string or {value, label} object */
export type NixFieldOption = string | { value: string; label: string };

/** Raw panel shape from the Nix panelsComputed output */
export interface NixPanel {
  id: string;
  module: string;
  title: string;
  description?: string | null;
  /** Module documentation in markdown format */
  readme?: string | null;
  icon?: string | null;
  type: string;
  order: number;
  enabled: boolean;
  fields: NixPanelField[];
  apps: Record<string, { enabled: boolean; config: Record<string, string> }>;
  /** Column definitions for PANEL_TYPE_TABLE */
  columns?: NixPanelColumn[];
  /** Row data for PANEL_TYPE_TABLE */
  rows?: Array<Record<string, string>>;
}

/** A single field inside a NixPanel */
export interface NixPanelField {
  name: string;
  type: string;
  value: string | null;
  options?: NixFieldOption[];
  label?: string | null;
  editable?: boolean;
  editPath?: string | null;
  placeholder?: string | null;
  /** Nix config path for saving field value (e.g., 'stackpanel.deployment.fly.organization') */
  configPath?: string | null;
  /** Help text shown below the field */
  description?: string | null;
}

/** A field definition from a PANEL_TYPE_APP_CONFIG panel */
export interface AppConfigField {
  name: string;
  type: string; // FIELD_TYPE_STRING, FIELD_TYPE_BOOLEAN, etc.
  label?: string;
  editable?: boolean;
  editPath?: string; // camelCase dot path e.g. "go.mainPackage"
  placeholder?: string;
  options?: NixFieldOption[];
  value?: string;
  /** Nix config path for saving field value */
  configPath?: string | null;
  /** Help text shown below the field */
  description?: string | null;
  /** Example value for additional context */
  example?: string | null;
}

/** A module panel with per-app config data */
export interface AppModulePanel {
  id: string;
  module: string;
  title: string;
  icon?: string;
  /** Module documentation in markdown format */
  readme?: string | null;
  fields: AppConfigField[];
  apps: Record<string, { enabled: boolean; config: Record<string, string> }>;
}

/** Metric item parsed from a STATUS panel's metrics JSON field */
export interface MetricItem {
  label: string;
  value: string;
  status?: "ok" | "warn" | "error";
}

/** Module metadata for the subnav */
export interface ModuleMeta {
  id: string;
  name: string;
  icon: string | null;
  description: string | null;
}

/** A group of panels belonging to a single module */
export interface ModuleGroup {
  id: string;
  label: string;
  icon?: string;
  panels: AppModulePanel[];
}
