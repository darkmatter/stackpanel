import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { z } from "zod";
import { components, limits, panelState } from "./author-schema";

const artifact = "nix/stackpanel/lib/ui/widget-catalog.v1.json";
const path = resolve(dirname(fileURLToPath(import.meta.url)), "../../../../../../../..", artifact);

function authorInput(schema: z.ZodType) {
  // Input also works for StatusView's transform: never publish its host-only output.
  const input = z.toJSONSchema(schema, { io: "input", reused: "inline", cycles: "throw" });
  delete input.$schema;
  return input;
}

export function widgetCatalog() {
  const entries = Object.entries(components).map(([name, widget]) => {
    return [
      name,
      {
        description: widget.description,
        container: widget.slots.includes("default"),
        props: authorInput(widget.props),
        bindings: widget.bindings,
      },
    ] as const;
  });
  return {
    version: 1,
    components: Object.fromEntries(entries),
    state: authorInput(panelState),
    limits,
  };
}

function render() {
  // The drift check and the repository formatter must agree on the checked-in bytes.
  return execFileSync("vp", ["fmt", "--stdin-filepath", path], {
    input: JSON.stringify(widgetCatalog(), null, 2),
    encoding: "utf8",
  });
}

export function checkWidgetCatalog() {
  if (!existsSync(path) || readFileSync(path, "utf8") !== render()) {
    throw new Error(`${artifact} is missing or stale. From apps/web run: vp run widgets:generate`);
  }
}

if (import.meta.main) {
  if (process.argv[2] === "--check") {
    checkWidgetCatalog();
  } else {
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, render());
  }
}
