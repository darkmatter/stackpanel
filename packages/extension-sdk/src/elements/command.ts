import { runAction, type ActionResult, type JsonObject } from "../bridge.js";
import { panelShadow, upgradeProperties } from "./dom.js";

/** A UI intent, not proof of authority. The runner must authorize every dispatch. */
export type PanelRunReason = "load-once" | "allow-automatic" | "selection-change";
export type PanelElementRun = (
  action: string,
  args: JsonObject,
  signal: AbortSignal,
  reason: PanelRunReason,
) => Promise<ActionResult>;

export interface PanelCommandElement extends HTMLElement {
  action: string;
  label: string;
  args: JsonObject;
  /** Undefined uses the ordinary sandbox bridge. Null disables all requests. */
  run: PanelElementRun | null | undefined;
}

function resultText({ stdout, stderr, json }: ActionResult): string {
  const blocks: string[] = [];
  if (stdout) blocks.push(`Stdout\n${stdout}`);
  if (stderr) blocks.push(`Stderr\n${stderr}`);
  if (json !== undefined) blocks.push(`JSON\n${JSON.stringify(json, null, 2)}`);
  return blocks.join("\n\n");
}

export function commandElement(kind: "action" | "status"): CustomElementConstructor {
  return class extends HTMLElement implements PanelCommandElement {
    static observedAttributes = ["action", "label"];
    #args: JsonObject = {};
    #run: PanelElementRun | null | undefined;
    #request?: AbortController;
    #updates: "off" | "enabling" | "on" = "off";
    #button = this.ownerDocument.createElement("button");
    #updatesButton = this.ownerDocument.createElement("button");
    #message = this.ownerDocument.createElement("p");
    #output = this.ownerDocument.createElement("pre");
    #updated = this.ownerDocument.createElement("time");

    constructor() {
      super();
      const controls = this.ownerDocument.createElement("div");
      this.#button.type = this.#updatesButton.type = "button";
      this.#button.addEventListener("click", () => {
        if (this.#updates === "off") void this.#execute("load-once");
      });
      controls.append(this.#button);
      if (kind === "status") {
        controls.append(this.#updatesButton);
        this.#updatesButton.addEventListener("click", () => {
          if (this.#updates !== "off" || this.#request) this.#reset();
          else if (this.#hasApp()) void this.#execute("allow-automatic");
        });
      }
      this.#message.setAttribute("role", "status");
      panelShadow(
        this,
        `div { display: flex; flex-wrap: wrap; gap: .5em; }
        p { margin: .35em 0; } pre { white-space: pre-wrap; overflow-wrap: anywhere; font-family: var(--font-mono, monospace); }
        time { color: var(--muted-foreground, inherit); }`,
        controls,
        this.#message,
        this.#output,
        this.#updated,
      );
    }

    get action() {
      return this.getAttribute("action") ?? "";
    }
    set action(value: string) {
      this.setAttribute("action", value);
    }
    get label() {
      return this.getAttribute("label") ?? "";
    }
    set label(value: string) {
      this.setAttribute("label", value);
    }
    get run() {
      return this.#run;
    }
    set run(value: PanelElementRun | null | undefined) {
      if (this.#run === value) return;
      this.#run = value;
      this.#reset();
    }
    get args() {
      return structuredClone(this.#args);
    }
    set args(value: JsonObject) {
      const { app, ...rest } = value;
      const { app: oldApp, ...oldRest } = this.#args;
      const sameInputs = JSON.stringify(rest) === JSON.stringify(oldRest);
      if (app === oldApp && sameInputs && Object.hasOwn(value, "app") === this.#hasApp()) return;
      const updateSelection =
        this.#updates === "on" && sameInputs && this.#hasApp() && Object.hasOwn(value, "app");
      this.#args = structuredClone(value);
      this.#clearRequest();
      if (updateSelection && !this.#unavailable()) void this.#execute("selection-change");
      else {
        this.#stopUpdates();
        this.#renderControls();
      }
    }

    connectedCallback() {
      upgradeProperties(this, ["action", "label", "run", "args"]);
      this.#renderControls();
    }
    disconnectedCallback() {
      this.#reset();
    }
    attributeChangedCallback(name: string, previous: string | null, value: string | null) {
      if (name === "action" && previous !== value) this.#reset();
      else this.#renderControls();
    }
    #hasApp() {
      return Object.hasOwn(this.#args, "app");
    }
    #unavailable() {
      if (!this.action.trim()) return "Choose an action to run.";
      if (this.#run === null) return "This action is unavailable. Check the panel permissions.";
      if (this.#hasApp() && !(typeof this.#args.app === "string" && this.#args.app.trim())) {
        return "Select an app to continue.";
      }
      return "";
    }
    #renderControls() {
      const unavailable = this.#unavailable();
      const active = this.#updates !== "off";
      this.#button.textContent =
        kind === "status" ? "Load once" : this.label || this.action || "Run action";
      this.#button.disabled = Boolean(unavailable || this.#request || active);
      this.#updatesButton.hidden = !this.#hasApp() && !this.#request;
      this.#updatesButton.textContent = active ? "Stop updates" : "Update on selection change";
      if (!active && this.#request) this.#updatesButton.textContent = "Cancel";
      this.#updatesButton.disabled = !active && !this.#request && Boolean(unavailable);
      if (unavailable) this.#message.textContent = unavailable;
      this.#output.hidden = !this.#output.textContent;
      this.#updated.hidden = !this.#updated.textContent;
    }
    #clearRequest() {
      const previous = this.#request;
      this.#request = undefined;
      previous?.abort();
      this.#message.textContent = "";
      this.#output.textContent = "";
      this.#updated.textContent = "";
      this.#updated.removeAttribute("datetime");
    }
    #stopUpdates() {
      if (this.#updates === "off") return;
      this.#updates = "off";
      // Hosts may discard an approval; an event never creates or extends one.
      this.dispatchEvent(new Event("sp-updates-stopped"));
    }
    #reset() {
      this.#clearRequest();
      this.#stopUpdates();
      this.#renderControls();
    }
    async #execute(reason: PanelRunReason) {
      if (!this.isConnected || this.#request || this.#unavailable()) return;
      const request = new AbortController();
      this.#request = request;
      if (reason === "allow-automatic") this.#updates = "enabling";
      this.#message.textContent = "Loading…";
      this.#output.textContent = "";
      this.#updated.textContent = "";
      this.#updated.removeAttribute("datetime");
      this.#renderControls();
      try {
        const run = this.#run ?? runAction;
        const result = await run(this.action, this.args, request.signal, reason);
        // Some runners cannot interrupt their underlying work. Never display its late result.
        if (request.signal.aborted) return;
        this.#output.textContent = resultText(result);
        if (result.exitCode !== 0) throw new Error(`Action exited with code ${result.exitCode}`);
        if (reason === "allow-automatic") this.#updates = "on";
        this.#message.textContent = "Completed.";
        const now = new Date();
        this.#updated.dateTime = now.toISOString();
        this.#updated.textContent = `Last updated: ${now.toLocaleString()}`;
      } catch (error) {
        if (request.signal.aborted) return;
        this.#message.textContent = `${error instanceof Error ? error.message : String(error)}. Check the action and its permissions, then retry.`;
        this.#stopUpdates();
      } finally {
        if (this.#request === request) {
          this.#request = undefined;
          this.#renderControls();
        }
      }
    }
  };
}
