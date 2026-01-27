// =============================================================================
// Shared panel types used by panels-panel, app-expanded-content, and renderers.
// =============================================================================

/** Raw panel shape from the Nix panelsComputed output */
export interface NixPanel {
  id: string;
  module: string;
  title: string;
  description?: string | null;
  icon?: string | null;
  type: string;
  order: number;
  enabled: boolean;
  fields: NixPanelField[];
  apps: Record<string, { enabled: boolean; config: Record<string, string> }>;
}

/** A single field inside a NixPanel */
export interface NixPanelField {
  name: string;
  type: string;
  value: string;
  options?: string[];
  label?: string | null;
  editable?: boolean;
  editPath?: string | null;
  placeholder?: string | null;
}

/** A field definition from a PANEL_TYPE_APP_CONFIG panel */
export interface AppConfigField {
  name: string;
  type: string; // FIELD_TYPE_STRING, FIELD_TYPE_BOOLEAN, etc.
  label?: string;
  editable?: boolean;
  editPath?: string; // camelCase dot path e.g. "go.mainPackage"
  placeholder?: string;
  options?: string[];
  value?: string;
}

/** A module panel with per-app config data */
export interface AppModulePanel {
  id: string;
  module: string;
  title: string;
  icon?: string;
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
