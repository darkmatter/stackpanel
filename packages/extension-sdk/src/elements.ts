import { commandElement, type PanelCommandElement } from "./elements/command.js";
import {
  appPickerElement,
  dataTableElement,
  metricElement,
  type PanelAppPickerElement,
  type PanelDataTableElement,
  type PanelMetricElement,
} from "./elements/display.js";

export type { PanelCommandElement, PanelElementRun, PanelRunReason } from "./elements/command.js";
export type {
  PanelAppOption,
  PanelAppPickerElement,
  PanelColumn,
  PanelDataTableElement,
  PanelMetricElement,
  PanelRow,
} from "./elements/display.js";

declare global {
  interface HTMLElementTagNameMap {
    "sp-metric": PanelMetricElement;
    "sp-data-table": PanelDataTableElement;
    "sp-app-picker": PanelAppPickerElement;
    "sp-status-view": PanelCommandElement;
    "sp-action": PanelCommandElement;
  }
}

/** Explicit per-document registration. Importing in a renderer or during SSR is inert. */
export function registerPanelElements(): void {
  if (typeof customElements === "undefined" || typeof HTMLElement === "undefined") return;
  function define(name: string, create: () => CustomElementConstructor) {
    if (!customElements.get(name)) customElements.define(name, create());
  }
  define("sp-metric", metricElement);
  define("sp-data-table", dataTableElement);
  define("sp-app-picker", appPickerElement);
  define("sp-status-view", () => commandElement("status"));
  define("sp-action", () => commandElement("action"));
}
