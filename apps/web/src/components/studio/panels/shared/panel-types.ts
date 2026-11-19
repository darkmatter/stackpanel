import type { JsonObject } from "@bufbuild/protobuf";
import type { ModuleAction as EvaluatedModuleAction } from "@stackpanel/proto/agent/v1/module";

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

/** An evaluated capability. Studio sends the ID and arguments, never the executable. */
export type ModuleAction = Pick<
  EvaluatedModuleAction,
  "label" | "description" | "icon" | "argsSchema" | "confirm" | "outputMode" | "invalidates"
>;

/** A panel from the evaluated panelsList. Nix supplies its slot, including the module default. */
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
  slot: string;
  nav?: { section: string; label?: string | null; icon?: string | null } | null;
  actions?: string[];
  rowActions?: string[];
  dataAction?: string | null;
  tabs?: string[];
  /** Untrusted json-render document; decoded before any elements mount. */
  spec?: unknown;
  /** Added by the agent to its project snapshot, never supplied by a module. */
  uiReview?: { revision: string; devOrigin?: string };
  uiBundle?: {
    package: string;
    entry: string;
    permissions: string[];
    actionIds?: string[] | null;
  } | null;
  fields: NixPanelField[];
  apps: Record<string, { enabled: boolean; config: Record<string, string> }>;
  /** Column definitions for PANEL_TYPE_TABLE */
  columns?: NixPanelColumn[];
  /** Row data for PANEL_TYPE_TABLE */
  rows?: JsonObject[];
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
  /** Writable path relative to stackpanel, e.g. deployment.fly.organization. */
  configPath?: string | null;
  /** Help text shown below the field */
  description?: string | null;
  example?: string | null;
}

/** Metric item parsed from a STATUS panel's metrics JSON field */
export interface MetricItem {
  label: string;
  value: string;
  status?: "ok" | "warn" | "error";
}
