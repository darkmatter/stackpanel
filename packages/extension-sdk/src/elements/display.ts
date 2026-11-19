import { panelShadow, upgradeProperties } from "./dom.js";

export interface PanelMetricElement extends HTMLElement {
  label: string;
  get value(): string;
  set value(value: string | number);
}

export type PanelColumn = { key: string; label: string } | { key: string; header: string };
export type PanelRow = Readonly<Record<string, string | number | boolean | null>>;
export interface PanelDataTableElement extends HTMLElement {
  columns: readonly PanelColumn[];
  rows: readonly PanelRow[];
}

export type PanelAppOption = string | { value: string; label: string };
export interface PanelAppPickerElement extends HTMLElement {
  label: string;
  value: string;
  apps: readonly string[];
  options: readonly PanelAppOption[];
}

export function metricElement(): CustomElementConstructor {
  return class extends HTMLElement implements PanelMetricElement {
    static observedAttributes = ["label", "value"];
    #term = this.ownerDocument.createElement("dt");
    #description = this.ownerDocument.createElement("dd");

    constructor() {
      super();
      const list = this.ownerDocument.createElement("dl");
      list.append(this.#term, this.#description);
      panelShadow(
        this,
        `dl, dd { margin: 0; } dt { color: var(--muted-foreground, inherit); }
        dd { font-weight: 600; font-variant-numeric: tabular-nums; }`,
        list,
      );
    }
    get label() {
      return this.getAttribute("label") ?? "";
    }
    set label(value: string) {
      this.setAttribute("label", value);
    }
    get value(): string {
      return this.getAttribute("value") ?? "";
    }
    set value(value: string | number) {
      this.setAttribute("value", String(value));
    }
    connectedCallback() {
      upgradeProperties(this, ["label", "value"]);
    }
    attributeChangedCallback() {
      this.#term.textContent = this.label;
      this.#description.textContent = this.value;
    }
  };
}

export function dataTableElement(): CustomElementConstructor {
  return class extends HTMLElement implements PanelDataTableElement {
    #columns: readonly PanelColumn[] = [];
    #rows: readonly PanelRow[] = [];
    #table = this.ownerDocument.createElement("table");

    constructor() {
      super();
      panelShadow(
        this,
        `:host { overflow-x: auto; } table { width: 100%; border-collapse: collapse; }
        th, td { text-align: start; padding: .35em .55em; border-bottom: 1px solid var(--border, GrayText); }`,
        this.#table,
      );
    }
    get columns() {
      return this.#columns;
    }
    set columns(value: readonly PanelColumn[]) {
      this.#columns = value;
      if (this.isConnected) this.#render();
    }
    get rows() {
      return this.#rows;
    }
    set rows(value: readonly PanelRow[]) {
      this.#rows = value;
      if (this.isConnected) this.#render();
    }
    connectedCallback() {
      upgradeProperties(this, ["columns", "rows"]);
      this.#render();
    }
    #render() {
      const head = this.ownerDocument.createElement("thead");
      const headings = head.insertRow();
      for (const column of this.columns) {
        const th = this.ownerDocument.createElement("th");
        th.scope = "col";
        th.textContent = "header" in column ? column.header : column.label;
        headings.append(th);
      }
      const body = this.ownerDocument.createElement("tbody");
      for (const record of this.rows) {
        const row = body.insertRow();
        for (const { key } of this.columns) {
          const value = Object.hasOwn(record, key) ? record[key] : null;
          row.insertCell().textContent = value == null ? "" : String(value);
        }
      }
      this.#table.replaceChildren(head, body);
    }
  };
}

export function appPickerElement(): CustomElementConstructor {
  return class extends HTMLElement implements PanelAppPickerElement {
    static observedAttributes = ["label", "value"];
    #options: readonly PanelAppOption[] = [];
    #label = this.ownerDocument.createElement("label");
    #select = this.ownerDocument.createElement("select");

    constructor() {
      super();
      this.#label.htmlFor = this.#select.id = "app";
      this.#select.addEventListener("change", (event) => {
        event.stopPropagation();
        this.value = this.#select.value;
        this.dispatchEvent(new Event("change", { bubbles: true, composed: true }));
      });
      panelShadow(
        this,
        "label { display: block; margin-bottom: .25em; }",
        this.#label,
        this.#select,
      );
    }
    get label() {
      return this.getAttribute("label") || "App";
    }
    set label(value: string) {
      this.setAttribute("label", value);
    }
    get value() {
      return this.#select.value;
    }
    set value(value: string) {
      this.setAttribute("value", value);
    }
    get apps() {
      return this.#options.map((item) => (typeof item === "string" ? item : item.value));
    }
    set apps(value: readonly string[]) {
      this.options = value;
    }
    get options() {
      return this.#options;
    }
    set options(value: readonly PanelAppOption[]) {
      this.#options = value;
      this.#render();
    }
    connectedCallback() {
      upgradeProperties(this, ["label", "apps", "options", "value"]);
      this.#render();
    }
    attributeChangedCallback() {
      this.#label.textContent = this.label;
      const value = this.getAttribute("value") ?? "";
      this.#select.value = value;
      if (this.#select.selectedIndex < 0) this.#select.value = "";
    }
    #render() {
      const options = this.ownerDocument.createDocumentFragment();
      const placeholder = this.ownerDocument.createElement("option");
      placeholder.value = "";
      placeholder.textContent = "Select an app";
      options.append(placeholder);
      for (const item of this.#options) {
        const option = this.ownerDocument.createElement("option");
        option.value = typeof item === "string" ? item : item.value;
        if (!option.value) continue;
        option.textContent = typeof item === "string" ? item : item.label;
        options.append(option);
      }
      this.#select.replaceChildren(options);
      this.#select.disabled = this.#select.length === 1;
      this.attributeChangedCallback();
    }
  };
}
